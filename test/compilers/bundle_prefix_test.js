import { assertSnapshot } from "testing/snapshot.ts";
import { beforeEach, describe, it } from "testing/bdd.ts";
import { join } from "std/path/mod.ts";

import main from "../../lib/proscenium/compilers/esbuild.js";

const root = join(Deno.cwd(), "test", "dummy");
const lightningcssBin = join(Deno.cwd(), "bin", "lightningcss");

describe("bundle: prefix", () => {
  beforeEach(() => {
    Deno.env.set("RAILS_ENV", "test");
    Deno.env.set("PROSCENIUM_TEST", "test");
  });

  it("js import", async (t) => {
    const result = await main("lib/bundle_import/index.js", {
      root,
      lightningcssBin,
      importMap: "config/import_maps/bundled.json",
    });

    await assertSnapshot(t, new TextDecoder().decode(result));
  });

  it("css import", async (t) => {
    const result = await main("lib/bundle_import/styles.css", {
      root,
      lightningcssBin,
      cssMixinPaths: [join(root, "lib")],
      importMap: "config/import_maps/bundled.json",
    });

    await assertSnapshot(t, new TextDecoder().decode(result));
  });
});
