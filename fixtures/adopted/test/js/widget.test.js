// C24 (#154): under `bun test` the gem's imports resolve from its dependency context too. The
// widget pins ms 2.0.0, which has no week unit; the app's ms 2.1.3 has one.
import { expect, test } from "bun:test";

import { ms as gemMs } from "@rubygems/stage_a_widget_a/index.js";
import { ms as appMs } from "../../lib/app.js";

test("the gem gets its own ms from its context, and the app its own", () => {
  expect(gemMs("1w")).toBeUndefined();
  expect(appMs("1w")).toBe(604800000);
});
