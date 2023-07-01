import { assertSnapshot } from "testing/snapshot.ts";
import { join } from "std/path/mod.ts";
import { beforeEach, describe, it } from "testing/bdd.ts";

import main from "../../lib/proscenium/compilers/esbuild.js";

const root = join(Deno.cwd(), "test", "dummy");
const lightningcssBin = join(Deno.cwd(), "bin", "lightningcss");

describe("rjs", () => {
  beforeEach(() => {
    Deno.env.set("RAILS_ENV", "test");
    Deno.env.set("PROSCENIUM_TEST", "test");
  });

  it("imports", async (t) => {
    const result = await main("lib/rjs.js", {
      root,
      lightningcssBin,
    });

    await assertSnapshot(t, new TextDecoder().decode(result));
  });
});
