// Bun plugin that hands every module in the graph to Proscenium.
//
//   Bun asks for  /lib/foo.js
//        │
//        ├─ onResolve  /^\//  ──▶ the real file on disk            (synchronous, from a lookup)
//        │
//        └─ onLoad  *.js|jsx|ts|tsx  ──▶ daemon "build"  ──▶ the module exactly as Rails serves
//                                                            it. Any import it still contains is
//                                                            /…-prefixed and extension-bearing
//                                                            ──▶ back to onResolve
//
// Nothing here decides how a module is built. The daemon fetches it through the app's own
// middleware, so bundling, minification, code splitting and externals are whatever the app
// configures - which is the whole point: a passing test means the browser gets the same thing.
//
// Four Bun behaviours shape this, all measured rather than assumed:
//
//   1. Plugin hooks only see a specifier containing a "." or a ":". Every extensionless form a
//      developer writes is therefore invisible here - which is fine, because Proscenium resolves
//      those before Bun is involved, and everything it emits carries an extension.
//   2. `onResolve` cannot await a promise ("onResolve() doesn't support pending promises yet"),
//      while `onLoad` can. Since a module's imports are only resolved after its contents load,
//      `build` returns those imports already resolved and `onResolve` is a synchronous lookup.
//   3. Exactly ONE `onLoad` may be registered. Register a second and both stop behaving, whether
//      the two live in one plugin or in two. So this dispatches by extension inside one hook.
//   4. A namespaced module can only be imported dynamically - a static `import` of one fails with
//      "Cannot find module 'ns:/path'". App code uses static imports, so nothing here is virtual:
//      every resolved path is a real file, which is also why the daemon materialises `.rjs`.

import { realpathSync } from "node:fs";

const LOADABLE = /\.(jsx?|tsx?|mjs|cjs|css)$/;
// Tolerates a trailing newline: JS `$` does not match before one without the `m` flag, and an
// inlined map arrives with one where the appended external comment does not.
const SOURCEMAP_COMMENT = /\n\/\/# sourceMappingURL=[^\n]*\n?$/;
const INLINE_SOURCEMAP = /sourceMappingURL=data:/;

/**
 * @param {object} options
 * @param {{send: (op: string, args?: object) => Promise<object>}} options.client daemon connection
 * @param {object} [options.config] the daemon's handshake payload
 * @param {boolean} [options.sourcemaps] inline source maps so stack traces point at real source.
 *   On by default - served output is minified, so a trace without one is unreadable. Free for a
 *   module the daemon builds, which embeds the map in the same build. Only an unbundled app pays
 *   anything: its modules are served, so each map is a second build (see TODOS.md).
 * @returns {import("bun").BunPlugin}
 */
export default function prosceniumPlugin({ client, config, sourcemaps = true }) {
  // Written by onLoad, read synchronously by onResolve. Keyed by url path, and again by the
  // absolute path it maps to, so onLoad can recover the url path Bun was originally asked for. A
  // specifier resolves to the same place for the life of a run, so nothing is ever invalidated.
  const byUrlPath = new Map();
  const byAbsPath = new Map();

  function remember(urlPath, hit) {
    byUrlPath.set(urlPath, hit);
    byAbsPath.set(hit.absPath, hit);

    // pnpm links packages into node_modules, and Bun hands onLoad the real path behind the link
    // while Proscenium reports the linked one. Keying both makes the lookup independent of which
    // form arrives.
    try {
      byAbsPath.set(realpathSync(hit.absPath), hit);
    } catch {
      // Nothing on disk under that path - a materialised or generated module. The direct key is
      // the only one that matters.
    }
  }

  async function urlPathFor(absPath) {
    const hit = byAbsPath.get(absPath);
    if (hit) return hit.urlPath;

    const fresh = await client.send("resolve", { path: absPath });
    remember(fresh.urlPath, fresh);
    return fresh.urlPath;
  }

  async function build(urlPath) {
    const { code, imports } = await client.send("build", { path: urlPath });

    // Every import this module makes, resolved ahead of the resolve hook that cannot await.
    for (const [urlPath, hit] of Object.entries(imports ?? {})) remember(urlPath, hit);

    if (!sourcemaps) return code.replace(SOURCEMAP_COMMENT, "");

    // The daemon inlines the map for anything it builds itself, which is one build rather than
    // two. Only a module it *served* - what Rails hands a browser - arrives with a map still to
    // fetch, and fetching it costs a second build of that module.
    if (INLINE_SOURCEMAP.test(code)) return code;

    try {
      const { code: map } = await client.send("build", { path: `${urlPath}.map` });
      const encoded = Buffer.from(map, "utf8").toString("base64");
      return code.replace(
        SOURCEMAP_COMMENT,
        `\n//# sourceMappingURL=data:application/json;base64,${encoded}`,
      );
    } catch {
      // A missing or unbuildable map is not worth failing a test run over.
      return code.replace(SOURCEMAP_COMMENT, "");
    }
  }

  return {
    name: "proscenium",
    config,

    setup(build_) {
      // Only ever sees paths Proscenium emitted: root-absolute, extension-bearing url paths, each
      // already resolved by the build of the module that imports it.
      build_.onResolve({ filter: /^\// }, (args) => {
        const hit = byUrlPath.get(args.path);

        // Not from a Proscenium build - a genuine filesystem import, or the entry test file. Let
        // Bun resolve it and report its own error rather than masking it.
        if (!hit) return undefined;

        return { path: hit.absPath };
      });

      build_.onLoad({ filter: LOADABLE }, async (args) => {
        // Importing a plain stylesheet from JS yields an empty object, which is exactly what a
        // bundled build produces for it (`var css_import_default = {}`) - the stylesheet itself
        // becomes a separate CSS output. A CSS *module* never reaches this branch: Proscenium
        // inlines it into the importing JS, class-name Proxy and all.
        if (args.path.endsWith(".css")) {
          return { contents: "export default {};", loader: "js" };
        }

        return { contents: await build(await urlPathFor(args.path)), loader: "js" };
      });
    },
  };
}
