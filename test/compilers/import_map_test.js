import { assertStringIncludes } from "testing/asserts.ts";
import { assertSnapshot } from "testing/snapshot.ts";
import { beforeEach, describe, it } from "testing/bdd.ts";
import { join } from "std/path/mod.ts";

import main from "../../lib/proscenium/compilers/esbuild.js";

const root = join(Deno.cwd(), "test", "dummy");
const lightningcssBin = join(Deno.cwd(), "bin", "lightningcss");

describe("import map", () => {
  beforeEach(() => {
    Deno.env.set("RAILS_ENV", "test");
    Deno.env.set("PROSCENIUM_TEST", "test");
  });

  it("map to a URL", async () => {
    const result = await main("lib/import_map/to_url.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/to_url.json",
    });

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import axios from "/url:https%3A%2F%2Fcdnjs.cloudflare.com%2Fajax%2Flibs%2Faxios%2F0.24.0%2Faxios.min.js";'
    );
  });

  it("from json", async () => {
    const result = await main("lib/import_map/bare_specifier.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/simple.json",
    });

    const code = new TextDecoder().decode(result);

    assertStringIncludes(code, 'import foo from "/lib/foo.js";');
  });

  it("from js", async () => {
    const result = await main("lib/import_map/as_js.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/as.js",
    });

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import pkg from "/lib/foo2.js";'
    );
  });

  it("should map to bundle: prefix", async (t) => {
    const result = await main("lib/import_map/bare_modules.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/bundle_prefix.json",
    });

    await assertSnapshot(t, new TextDecoder().decode(result));
  });

  it("should map to bundle-all: prefix", async (t) => {
    const result = await main("lib/import_map/bare_modules.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/bundle_all_prefix.json",
    });

    await assertSnapshot(t, new TextDecoder().decode(result));
  });

  it("should use root as resolveDir", async (t) => {
    const result = await main("lib/import_map/nested/index.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/external_imports/basic.json",
    });

    await assertSnapshot(t, new TextDecoder().decode(result));
  });

  it("should use root as resolveDir when using bundle: prefix", async (t) => {
    const result = await main("npm:@external/three/src/prop_types", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/external_imports/bundle.json",
    });

    await assertSnapshot(t, new TextDecoder().decode(result));
  });

  it("should use root as resolveDir when using bundle-all: prefix", async (t) => {
    const result = await main("npm:@external/three/src/prop_types", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/external_imports/bundle-all.json",
    });

    await assertSnapshot(t, new TextDecoder().decode(result));
  });

  it("maps imports via trailing slash", async () => {
    const result = await main("lib/component.jsx", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/trailing_slash_import.json",
    });

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import { jsx } from "/url:https%3A%2F%2Fesm.sh%2Freact%4018.2.0%2Fjsx-runtime"'
    );
  });

  it("resolves imports from a node_module", async () => {
    const result = await main("node_modules/is-ip/index.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/npm.json",
    });

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import ipRegex from "/url:https%3A%2F%2Fesm.sh%2Fip-regex";'
    );
  });

  it("supports scopes", async () => {
    const result = await main("lib/import_map/scopes.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/scopes.json",
    });

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import foo from "/lib/foo4.js";'
    );
  });

  it("should map bare modules", async () => {
    const result = await main("lib/import_map/bare_modules.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/bare_modules.json",
    });

    assertStringIncludes(
      new TextDecoder().decode(result),
      'import { isIP } from "/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js";'
    );
  });
});
