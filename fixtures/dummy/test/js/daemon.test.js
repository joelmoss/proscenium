import { afterEach, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";

// The client on its own, against a fake daemon this test controls, so the daemon can be made to
// die. Not through a second `register()`, which would leave a dead plugin registered for the rest
// of the run.
import { Daemon } from "../../../../lib/proscenium/runtime/bootstrap.js";

// Long enough for a rejection that is coming, short enough that a request nothing will ever
// settle fails the test rather than hanging it.
const SETTLE_MS = 1_000;

let server;
let dir;

afterEach(() => {
  server?.stop(true);
  if (dir) rmSync(dir, { recursive: true, force: true });
  server = dir = undefined;
});

// A daemon that hands each request to `onRequest` along with the server side of the socket.
async function connectTo(onRequest) {
  mkdirSync("tmp/proscenium", { recursive: true });
  dir = mkdtempSync(join("tmp/proscenium", "t-"));
  const unix = join(dir, "d.sock");

  server = Bun.listen({ unix, socket: { data: (socket, chunk) => onRequest(socket, `${chunk}`) } });

  return Daemon.connect(unix);
}

function settles(promise) {
  return Promise.race([
    promise.then(
      () => "resolved",
      (error) => error,
    ),
    Bun.sleep(SETTLE_MS).then(() => "still pending"),
  ]);
}

test("a request after the daemon has gone rejects instead of hanging", async () => {
  const client = await connectTo((socket) => socket.end());

  // Pending when the daemon goes, so its rejection proves the close has been seen.
  const first = await settles(client.send("build", { path: "/lib/a.js" }));
  expect(first).toBeInstanceOf(Error);

  const second = await settles(client.send("build", { path: "/lib/b.js" }));
  expect(second).toBeInstanceOf(Error);
  expect(second.message).toContain("closed the connection");
});

test("a request after an unreadable reply rejects with that reply's error", async () => {
  // Garbage once, then silence: only the client's own state can settle the second request.
  let replied = false;
  const client = await connectTo((socket) => {
    if (!replied) socket.write("not json\n");
    replied = true;
  });

  const first = await settles(client.send("build", { path: "/lib/a.js" }));
  expect(first).toBeInstanceOf(SyntaxError);

  // The socket is still open, but nothing on it can be trusted any more.
  const second = await settles(client.send("build", { path: "/lib/b.js" }));
  expect(second).toBe(first);
});
