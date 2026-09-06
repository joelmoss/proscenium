import { expect, test } from "bun:test";
import styles from "/lib/bun_fixtures/css_module.js";

// The exact class name the browser gets in this environment, and the same one the `css_module`
// view helper emits. Identifiers are minified in production only, and an unminified one carries a
// path-derived suffix - so this is the full name, spelled out rather than pattern-matched. A
// harness that chose its own build settings would fail here rather than quietly testing class
// names the app never serves.
test("a css module imported from js exports the app's real class names", () => {
  expect(styles.myClass).toBe("myClass_0d45f40a_lib-styles-module");
});
