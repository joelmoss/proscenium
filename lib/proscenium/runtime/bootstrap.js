// Starts a Proscenium daemon and registers the Bun plugin against it.
//
// The app-side preload is deliberately thin - it locates the gem and calls `register()` - so the
// protocol, the spawn, and the failure handling all live here and travel with the gem rather than
// being copy-pasted into every app and drifting.

import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";

const DEFAULT_TIMEOUT_MS = 30_000;

class Daemon {
  #socket;
  #pending = new Map();
  #buffer = "";
  #nextId = 1;

  // Decodes across chunk boundaries. `chunk.toString()` decodes each chunk on its own, so a
  // multi-byte character split by the socket becomes U+FFFD on both sides - a module whose bytes
  // silently differ from the ones Rails served, which is the one thing this harness exists to
  // rule out. Any non-ASCII in app source (an emoji, CJK text, a smart quote esbuild kept) hits
  // it once a reply outgrows one chunk.
  #decoder = new TextDecoder();

  constructor(socket) {
    this.#socket = socket;
  }

  static async connect(socketPath) {
    let daemon;
    const socket = await Bun.connect({
      unix: socketPath,
      socket: {
        data: (_sock, chunk) => daemon.#onData(chunk),
        close: () => daemon.#rejectAll(new Error("proscenium daemon closed the connection")),
        error: (_sock, error) => daemon.#rejectAll(error),
      },
    });
    daemon = new Daemon(socket);
    return daemon;
  }

  send(op, args = {}) {
    return new Promise((resolve, reject) => {
      const id = this.#nextId++;
      this.#pending.set(id, { resolve, reject });
      this.#socket.write(`${JSON.stringify({ id, op, ...args })}\n`);
    });
  }

  close() {
    this.#socket.end();
  }

  #onData(chunk) {
    this.#buffer += this.#decoder.decode(chunk, { stream: true });

    let newline;
    while ((newline = this.#buffer.indexOf("\n")) !== -1) {
      const line = this.#buffer.slice(0, newline);
      this.#buffer = this.#buffer.slice(newline + 1);
      if (!line.trim()) continue;

      let reply;
      try {
        reply = JSON.parse(line);
      } catch (error) {
        this.#rejectAll(error);
        return;
      }

      const waiting = this.#pending.get(reply.id);
      if (!waiting) continue;
      this.#pending.delete(reply.id);

      if (reply.ok) waiting.resolve(reply);
      else waiting.reject(new Error(reply.error ?? "proscenium daemon returned an error"));
    }
  }

  #rejectAll(error) {
    for (const { reject } of this.#pending.values()) reject(error);
    this.#pending.clear();
  }
}

/**
 * Spawn the daemon and wait for its socket to accept a connection.
 *
 * The socket path is chosen here rather than announced by the child, so nothing is ever read from
 * a pipe. That is not tidiness: under `bun test`, once happy-dom's GlobalRegistrator has run and a
 * DOM-touching package (`@testing-library/react`, say) has been imported, every subsequent
 * `Bun.spawn`/`Bun.spawnSync` with `stdout: "pipe"` yields a zero-length buffer - exit status 0,
 * empty stderr, no bytes. Unix sockets are unaffected, and so is a file-backed stdout. A pipe-based
 * announcement is therefore unusable from the one position in the preload order this plugin can be
 * registered in, which is last, after the app's test tooling is loaded and cached.
 *
 * Rails also fails to boot for ordinary reasons - a pending migration, a database that is not
 * running, a bad initializer - so polling is raced against the child exiting and against a
 * timeout. That turns "bun test hangs with no output", the worst failure shape there is, into a
 * named error with Rails' own stderr already on the terminal.
 */
async function spawnDaemon({ env, timeoutMs }) {
  // A path relative to this process' cwd, not an absolute one. A unix socket path is capped at 104
  // bytes on macOS and 108 on Linux - `sun_path` is a fixed-size array inside `sockaddr_un`, sized
  // to fit a 4.2BSD mbuf and frozen ever since by ABI - and the kernel only ever sees the bytes
  // handed to `bind`/`connect`. So `tmp/proscenium/d-XXXXXX/d.sock` spends 30 of them wherever the
  // app lives, where the absolute equivalent spends 30 plus the app's own path and a CI checkout or
  // a nested monorepo package clears the cap on its own.
  //
  // `Bun.spawn` below is given no `cwd`, so the daemon inherits this one and both ends resolve the
  // same relative path by construction. A `chdir` between here and `connect` would break that, and
  // surfaces as the startup timeout further down.
  //
  // The directory is created exclusively and 0700, and the socket lives inside it, because the
  // name alone is no protection: the full path is passed as `rails runner` argv below, so `ps`
  // shows it to every user on the machine, and the client connects to whatever answers - for the
  // seconds Rails takes to boot, with no way to tell its own child from a squatter. Whoever binds
  // first answers every `build`, and a `build` reply is JavaScript this process executes. Same
  // reasoning, and the same fix, as the gem-dir file in the preload template.
  mkdirSync("tmp/proscenium", { recursive: true });
  const socketDir = mkdtempSync(join("tmp", "proscenium", "d-"));
  // Must match Server::SOCKET_NAME. The daemon is handed the directory, not the path.
  const socketPath = join(socketDir, "d.sock");

  const command = [
    "bundle",
    "exec",
    "rails",
    "runner",
    "-e",
    env,
    'require "proscenium/runtime/server"; ' +
      `Proscenium::Runtime::Server.start(socket_dir: ${JSON.stringify(socketDir)}, ` +
      `parent_pid: ${process.pid})`,
  ];

  // No pipes at all, in either direction. The daemon's default parent-liveness watch is EOF on its
  // own stdin, which a pipe from here would provide - but in the poisoned state described above
  // that pipe arrives already closed, so the daemon would shut down the moment it finished
  // booting. `parent_pid` above replaces it with a poll of this process.
  const proc = Bun.spawn(command, { stdin: "ignore", stdout: "inherit", stderr: "inherit" });

  // Connected with the real client rather than probed and thrown away: `Daemon` wires its
  // handlers up at connect time, and a bare `Bun.connect` with no handlers is not a connection
  // this can hand on.
  //
  // `settled` is what stops the loop. Losing the race below does not cancel a promise, so
  // without it this kept retrying every 50ms for the life of the process after `register()` had
  // already rejected - and a caller that handles the error stays alive, so the loop does too.
  let settled = false;
  const listening = (async () => {
    while (!settled) {
      try {
        return await Daemon.connect(socketPath);
      } catch {
        // Not up yet. The daemon boots Rails first, so the first few attempts always miss.
        await Bun.sleep(50);
      }
    }
    throw new Error("proscenium daemon startup was abandoned");
  })();

  const exited = proc.exited.then((code) => {
    throw new Error(
      `the proscenium daemon exited with status ${code} before its socket accepted a connection.\n` +
        `Command: ${command.join(" ")}\n` +
        "Its output is above - a Rails boot failure is the usual cause.",
    );
  });

  let timer;
  const timedOut = new Promise((_resolve, reject) => {
    timer = setTimeout(
      () =>
        reject(
          new Error(
            `the proscenium daemon did not accept a connection within ${timeoutMs}ms.\n` +
              `Command: ${command.join(" ")}`,
          ),
        ),
      timeoutMs,
    );
  });

  try {
    const client = await Promise.race([listening, exited, timedOut]);
    return { proc, client, socketDir };
  } catch (error) {
    // The timeout path in particular leaves a booted Rails process behind: it never connected,
    // so nothing else is going to close it, and its own parent-pid watch only fires once THIS
    // process exits - which may be a whole test run later.
    proc.kill();
    rmSync(socketDir, { recursive: true, force: true });
    throw error;
  } finally {
    settled = true;
    clearTimeout(timer);
  }
}

/**
 * Start a daemon, register the plugin, and return both so a caller can shut down explicitly.
 *
 * @param {object} [options]
 * @param {string} [options.env] Rails environment for the daemon. Defaults to RAILS_ENV or "test".
 * @param {number} [options.timeoutMs] how long to wait for the daemon to come up.
 * @param {boolean} [options.sourcemaps] inline source maps into built modules. On by default, and
 *   free unless the app is unbundled - see the plugin's own note.
 */
export async function register(options = {}) {
  const env = options.env ?? Bun.env.RAILS_ENV ?? "test";
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const { proc, client, socketDir } = await spawnDaemon({ env, timeoutMs });
  const { config } = await client.send("handshake");

  // Imported by its path relative to this file, not by the `pluginPath` the handshake reports.
  // The daemon is whatever answered on the socket, so taking a code path from it would mean
  // importing and running something a peer chose - and this file already knows where its own
  // sibling lives. `pluginPath` stays in the handshake for a client that is not shipped with the
  // gem, which has no such sibling to import.
  const { default: prosceniumPlugin } = await import(new URL("./bun.js", import.meta.url).href);
  Bun.plugin(prosceniumPlugin({ client, config, sourcemaps: options.sourcemaps }));

  // The daemon polls this process' pid (see `parent_pid` above), so it exits when this process
  // does even if the exit is not a clean one. This is belt and braces for the clean case.
  //
  // The daemon is told to remove the socket directory too (`socket_dir:` above), because this
  // handler is not reliable: measured on Bun 1.3.13, three runs left three empty directories
  // behind even with the `rmSync` below. The daemon's own parent-pid watch exits cleanly and runs
  // its `ensure`, so that is the path that actually cleans up. This stays as the fast case.
  const stop = () => {
    try {
      client.close();
    } catch {
      // Already gone.
    }
    proc.kill();
    rmSync(socketDir, { recursive: true, force: true });
  };
  process.on("exit", stop);

  return { client, config, proc, stop };
}

export default register;
