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
 * Spawn the daemon and wait for it to announce its socket path.
 *
 * Rails fails to boot for ordinary reasons - a pending migration, a database that is not running,
 * a bad initializer - and the announcement never arrives. Racing it against the child exiting and
 * against a timeout turns "bun test hangs with no output", the worst failure shape there is, into a
 * named error with Rails' own stderr already on the terminal.
 */
async function spawnDaemon({ env, timeoutMs }) {
  const command = [
    "bundle",
    "exec",
    "rails",
    "runner",
    "-e",
    env,
    'require "proscenium/runtime/server"; Proscenium::Runtime::Server.start',
  ];

  const proc = Bun.spawn(command, { stdin: "pipe", stdout: "pipe", stderr: "inherit" });

  const announced = (async () => {
    const decoder = new TextDecoder();
    let buffer = "";
    for await (const chunk of proc.stdout) {
      buffer += decoder.decode(chunk, { stream: true });
      const newline = buffer.indexOf("\n");
      if (newline !== -1) return buffer.slice(0, newline).trim();
    }
    throw new Error("the proscenium daemon exited before announcing its socket");
  })();

  const exited = proc.exited.then((code) => {
    throw new Error(
      `the proscenium daemon exited with status ${code} before announcing its socket.\n` +
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
            `the proscenium daemon did not announce its socket within ${timeoutMs}ms.\n` +
              `Command: ${command.join(" ")}`,
          ),
        ),
      timeoutMs,
    );
  });

  try {
    const socketPath = await Promise.race([announced, exited, timedOut]);
    return { proc, socketPath };
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
  const { proc, socketPath } = await spawnDaemon({ env, timeoutMs });
  const client = await Daemon.connect(socketPath);
  const { config } = await client.send("handshake");

  const { default: prosceniumPlugin } = await import(config.pluginPath);
  Bun.plugin(prosceniumPlugin({ client, config, sourcemaps: options.sourcemaps }));

  // The daemon also watches its stdin, so it exits when this process does even if the exit is not
  // a clean one. This is belt and braces for the clean case.
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
