// Starts a Proscenium daemon and registers the Bun plugin against it.
//
// The app-side preload is deliberately thin - it locates the gem and calls `register()` - so the
// protocol, the spawn, and the failure handling all live here and travel with the gem rather than
// being copy-pasted into every app and drifting.

const DEFAULT_TIMEOUT_MS = 30_000;

class Daemon {
  #socket;
  #pending = new Map();
  #buffer = "";
  #nextId = 1;

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
    this.#buffer += chunk.toString();

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
  // Not os.tmpdir(): a unix socket path is capped at ~104 bytes, and a sandboxed or CI TMPDIR can
  // spend most of that on its own.
  const socketPath = `/tmp/proscenium-${process.pid}-${Date.now().toString(36)}.sock`;

  const command = [
    "bundle",
    "exec",
    "rails",
    "runner",
    "-e",
    env,
    'require "proscenium/runtime/server"; ' +
      `Proscenium::Runtime::Server.start(socket_path: ${JSON.stringify(socketPath)}, ` +
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
  const listening = (async () => {
    for (;;) {
      try {
        return await Daemon.connect(socketPath);
      } catch {
        // Not up yet. The daemon boots Rails first, so the first few attempts always miss.
        await Bun.sleep(50);
      }
    }
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
    return { proc, client };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Start a daemon, register the plugin, and return both so a caller can shut down explicitly.
 *
 * @param {object} [options]
 * @param {string} [options.env] Rails environment for the daemon. Defaults to RAILS_ENV or "test".
 * @param {number} [options.timeoutMs] how long to wait for the daemon to come up.
 * @param {boolean} [options.sourcemaps] inline source maps into built modules.
 */
export async function register(options = {}) {
  const env = options.env ?? Bun.env.RAILS_ENV ?? "test";
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const { proc, client } = await spawnDaemon({ env, timeoutMs });
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
  const stop = () => {
    try {
      client.close();
    } catch {
      // Already gone.
    }
    proc.kill();
  };
  process.on("exit", stop);

  return { client, config, proc, stop };
}

export default register;
