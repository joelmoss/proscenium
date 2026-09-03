import { expect, test } from "bun:test";

// Static imports, because that is how app and test code is written - and because Bun only
// dispatches its plugin load hook for static imports (see lib/proscenium/runtime/bun.js).
//
// This one module covers six resolution shapes at once: a full path, an extensionless specifier,
// a package with no filename, a transitive dependency, an app path reached from inside a package,
// and out-of-root pnpm link:/file: dependencies.
import "/lib/importing/package.js";
import * as pkg from "pkg";
import { railsEnv, nodeEnv } from "/lib/bun_fixtures/env.js";

test("root-absolute, extensionless, package and out-of-root specifiers all resolve", () => {
  expect(true).toBe(true);
});

// ESM packages only. Unbundled mode serves each module on its own, and a CommonJS package (React
// 18's index.js, for one) cannot be loaded that way - the same limitation
// `config.proscenium.bundle = false` already has in the browser.
test("bare npm packages resolve through proscenium", () => {
  expect(pkg).toBeDefined();
});

test("proscenium.env and process.env are substituted at build time", () => {
  expect(railsEnv).toBe("test");
  expect(nodeEnv).toBe("test");
});
