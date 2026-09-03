import { expect, test } from "bun:test";
import styles from "/lib/bun_fixtures/css_module.js";

// The exact class name the browser gets, and the same one the `css_module` view helper emits.
// Anchored deliberately: an unminified build appends a path-derived suffix
// (`myClass_0d45f40a_lib-styles-module`), so a harness that chose its own build settings would
// fail here rather than quietly testing class names the app never serves.
test("a css module imported from js exports the app's real class names", () => {
  expect(styles.myClass).toMatch(/^myClass_[a-f0-9]{8}$/);
});
