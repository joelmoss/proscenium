import { expect, test } from "bun:test";
import greeting from "/lib/bun_fixtures/rjs.js";

// Server rendered JavaScript, rendered by the app's own route through Rails.application.call.
// No dev server is running.
test("rjs is rendered by the rails app", () => {
  expect(greeting).toBe("hello");
});
