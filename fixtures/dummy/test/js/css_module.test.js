import { expect, test } from "bun:test";
import styles from "/lib/bun_fixtures/css_module.js";

// The class name the browser gets in this environment, and the same one the `css_module` view
// helper emits. Identifiers are minified in production only, so the name carries a path-derived
// suffix here - and the suffix is the assertion that matters: a harness that chose its own build
// settings would drop it, and quietly test class names the app never serves.
//
// The digest itself is `sha1(absolute path)[0:8]`, so it differs per checkout directory and
// cannot be spelled out - a literal passes on the machine it was written on and fails in CI.
test("a css module imported from js exports the app's real class names", () => {
  expect(styles.myClass).toMatch(/^myClass_[a-f0-9]{8}_lib-styles-module$/);
});
