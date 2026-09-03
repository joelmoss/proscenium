import { expect, test } from "bun:test";
import AtIcon from "/lib/bun_fixtures/svg.tsx";

test("an svg imported from tsx is a component", () => {
  expect(typeof AtIcon).toBe("function");
});
