# TODOS

## Infrastructure

### Skip the extension-finding `Resolve` in the Bundler plugin

**What:** 58 of the distinct specifiers London's `appointment/create/component.jsx` sends to
`build.Resolve` are relative or absolute paths with no extension, and the Bundler plugin calls
`Resolve` for them only to find the extension before it applies aliases and gem URL mapping.
Avoiding that call means doing that work in Proscenium, or letting esbuild resolve them and
applying aliases afterwards.

**Why:** It is the lever left over after the directory-listing cache below took the easy half. The
cache made each of those calls cheap; this removes them.

**Context:** Riskier than the cache, because it moves resolution logic across the esbuild boundary
rather than making the existing calls faster. Also tried and rejected on the way to the cache: a
process-wide directory cache validated by each directory's `ModKey` (mtime, with esbuild's 3 second
racy-timestamp gap). About -50% on the big builds, no better than the per-build cache, and it adds
staleness risk across builds.

**Effort:** M
**Priority:** P3
**Depends on:** None

### Persistent esbuild Context/Rebuild

**What:** Switch `build_to_string`/`resolve` from one-shot `esbuild.Build()` calls to esbuild's
persistent `Context()`+`Rebuild()` API so that parsed files and file contents survive across calls.

**Why (revised):** This item used to say the directory-scan cache would survive across calls. It
would not. In esbuild's `api_impl.go`, `contextImpl` creates the long-lived file system with
`DoNotCache: true` ("do not cache calls to ReadDirectory()"), and `rebuildImpl` creates a new
`realFS` for every rebuild, so directory listings are cached for one rebuild only. That is where the
time went on a real app (see the item above, now done: about 46% `readdir`, 10% `lstat`, 8.5% GC,
about 11% reading files), so this change would have left most of it in place. What does survive is
the `CacheSet`: file contents (revalidated with `ModKey` on every read), parsed JS, CSS and JSON, and
source indexes. That saves parse and read work on files that have not changed, and nobody has
measured how much that is.

**Context:** The two questions this item was blocked on are answered. (1) Can `EntryPoints` change
between `Rebuild()` calls? No: `contextImpl` validates the options once and captures the entry
points in `rebuildArgs`, so it would take one Context per entry point, and per config. Proscenium
builds a different entry point per request, so the memory cost of holding them is unknown. (2)
Is cache invalidation safe? For file contents esbuild's `FSCache` stats the file on every read and
re-reads it when the `ModKey` differs, and when the mtime is within 3 seconds of now it does not
trust it. Directory listings are never cached across rebuilds, by design. Before spending L effort,
measure what an unchanged-entry `Rebuild()` actually saves on a real app.

**Effort:** L
**Priority:** P4 (was P3)
**Depends on:** A measurement showing parse and read time is worth saving

### Full concurrency audit of esbuild-internal

**What:** A general audit of the vendored esbuild-internal fork (`../esbuild-internal`) for package-level globals unsafe under concurrent use - broader than the specific concurrent-`Build()`/`Resolve()` workload in the global config refactor's Phase 4.

**Why:** Phase 4's audit only exercises the specific code paths Proscenium calls (`Build`, `Resolve`). A general audit would cover the rest of the fork's surface (`Transform`, other entry points) that this refactor doesn't touch but that you maintain.

**Context:** Only came up as a byproduct of scoping the global config refactor's Phase 4. The fork is large; a general audit is a separate, open-ended effort with no clear trigger or deadline. Phase 4's narrower audit already covers the load-bearing case (what Proscenium actually calls) - this would only matter if something outside that surface starts getting exercised concurrently too.

**Effort:** XL
**Priority:** P4
**Depends on:** Global config refactor Phase 4 landing first

## Frontend

### One esbuild build per module, not two

**What:** Return a module's source map from the same `esbuild.Build()` that produced its code,
instead of rebuilding. Today `internal/builder/build.go` strips a `.map` suffix from the entry
point and runs a complete independent build, so any module whose map is fetched costs two full
builds.

**Mostly handled.** `SourcemapInline` embeds the map in the code, so one build returns both, and
the Bun daemon uses it for every module it builds. What is left is the case where the map has to
be a separate file: a browser in development with devtools open, which fetches `<path>.map` after
the code, and the unbundled Bun path, where each module is served rather than built.

**Separately: Bun does not apply the map at all.** Measured on 1.3.13, a module returned from a
plugin's `onLoad` gets no source-map treatment - a thrown error names the bundled entry point at
line 1, identically with an inline map, with a fetched-and-inlined one, and with none. Setting
esbuild's `SourceRoot` (the map's `sources` are written relative to `OutputDir`, which is nowhere
near where Bun loaded the module from) changes nothing, which is what says Bun is not reading the
map rather than misreading it. So the maps the harness ships are inert until Bun supports this;
they are kept because they now cost nothing. Debugging a test failure means reading built output.

**Why:** `TODOS.md` records that most of a build's CPU is esbuild reading and resolving files, not
transforming them (about 55% in `readdir` and `lstat` on a real app), so build count is most of the
cost. Measured in the dummy app,
development, mean of 20 builds each - code plus separate map against a single inlined build:

| entry point | two builds | one inlined build |
|---|---|---|
| `lib/importing/package.js` | 29.2ms | 12.2ms |
| `lib/css_modules/bare_import.js` | 13.7ms | 4.0ms |
| `app/views/articles/index.jsx` | 2.9ms | 1.5ms |

The map is free when it rides along, and costs as much as the code when it does not.

**Context:** esbuild already emits both output files from one call (`Sourcemap: SourceMapExternal`),
and `build_to_string.go` already contains the logic to pick one of two output files by suffix - so
the build is being thrown away rather than being unavailable. The fix needs a way to ask for both
at once, which means the cgo surface in `main.go` and its mirror in `lib/proscenium/builder.rb`
(CLAUDE.md flags that pairing). The daemon would then cache the pair under one key.
`register({ sourcemaps: false })` in `lib/proscenium/runtime/bun.js` skips what remains, at the
cost of readable failures in a minified build.

**Effort:** M
**Priority:** P2
**Depends on:** None.

### Node, Vitest and Deno test adapters

**What:** Adapters so `node --test`, Vitest and Deno can run app JavaScript, driving the same
daemon protocol as the Bun plugin (`lib/proscenium/runtime/server.rb`).

**Why:** Issue #65 asks for "Bun, Deno or Node". v1 ships Bun only, so the issue is half answered.
The daemon is mostly runtime-agnostic, but not entirely: `op_handshake` hands every client the Bun
plugin's path, and `RUNTIME_MODULES` adds Bun's own module namespaces to the entry build's
externals. An adapter is a new plugin file plus letting the client say which runtime is asking.

**Context:** Three constraints are already established and are the expensive part to rediscover.
Node's `resolve` hook sees extensionless and bare specifiers directly, so the Node adapter is
*simpler* than Bun's - but it must use async `module.register`, not the synchronous
`module.registerHooks`, which cannot await the daemon. Node also rejects unknown import attributes
at parse time (`ERR_IMPORT_ATTRIBUTE_UNSUPPORTED`), so every file has to go through the load hook
for `with { unbundle: 'true' }` to survive. Deno has no load hook at all, so it can only ever do
resolution - no CSS modules, SVG components or i18n.

**Effort:** M
**Priority:** P3
**Depends on:** The Bun harness landing first.

## Simplification audit

### Structural simplifications from the 2026-09-08 audit

**What:** Work through the ranked findings in `AUDIT.md` - a whole-repository read-only audit at
commit `5edd7363` covering the Ruby engine, the Go/esbuild core, the FFI contract between them,
the Bun harness and the browser React manager. 34 accepted findings, each with `file:line`
evidence, a smallest-credible scope, regression risks and the validation it needs.

**`AUDIT.md` is the record.** Its Progress table carries what is done, which commit did it, and
every correction implementation produced along the way. Read its "AUDIT-THE-AUDIT — pass 4"
section before starting anything: it is the final adjudication and overrides the per-lane
priorities earlier in that file, rejecting three findings, demoting five and reversing one
dependency chain. Do not copy any of that here - two copies drift.

**Next:** `F-GORESOLVE-1`, the last of the three `@rubygems` consumers, and only then
`F-GOUTILS-1`'s step 2 and step 3 (pass 4 ruling 1, consumers-by-deletion first). Nothing still
open misserves or crashes on a client-supplied URL - the two that did, and the two `internal/css`
defects before them, are fixed. What remains is materiality rather than breakage. Several findings
must write the first test for the code they touch; `AUDIT.md`'s pattern P7 lists which, and for
those the diff is small and the test is the work.

**Still open from the Codex adversarial pass** (`AUDIT.md`, "CODEX ADVERSARIAL PASS"): findings 3,
9 and 10 are all one function, `internal/plugin/i18n.go`'s change detector and publish path - an
edit preserving mtime is invisible, concurrent rebuilds can publish an older payload over a newer
one, and a `ReadDir` failure caches `{}` forever while reporting itself as a successful load. Worth
doing as one diff rather than three. Finding 2, vendor's permanent caching with no ETag or
versioned URL, is a policy call about URL versioning rather than a bug.

**Worth keeping from the middleware fixes:** normalise a request path once, then route, check and
build from that single value. Three separate defects were the same shape - `Chunks` reading a raw
path the file handler later normalised, and `find_type` / `file_readable?` / `path_to_build`
disagreeing three ways.

**Effort:** XL in total; individual findings range from one line to a day.
**Priority:** P3 for what remains. One bug lead came out of `F-GOBUNDLE-1` and is recorded in
`AUDIT.md` rather than fixed: an extensionless `@rubygems/` specifier that esbuild cannot resolve
leaks an absolute filesystem path into the built output, because the top-level handler returns
without passing through the catch-all's URL-conversion tail.
**Depends on:** Nothing external. Internal ordering is in `AUDIT.md` pass 4.

## Robustness

### Recover from panics in esbuild plugin callbacks (esbuild fork)

**What:** Wrap the plugin callbacks in the esbuild fork (`OnResolve`, `OnLoad` and the plugin
`Resolve` API) in `recover()`, so a panic becomes a build error.

**Why:** There is no `recover()` anywhere in the shipped Go code, and a panic in a plugin goroutine
aborts the whole process, which for this library is the Ruby server that loaded it. In the fork,
`parseFile` calls `runOnLoadPlugins` (`bundler/bundler.go:164`) before its own `defer recover()`
(`:257-258`), so an `OnLoad` panic is unrecovered, while an `OnResolve` panic raised while resolving
a parsed file's imports is recovered into a build error. The one explicit `panic(err)` in the
rubygems `OnLoad` was removed by the bundless alias fix; implicit ones (a nil dereference, an
unchecked type assertion) are still possible. The five cgo exports in `main.go` have no recover
either (`AUDIT.md`).

**Context:** One recover in the fork protects every present and future plugin, so that is where the
leverage is. A recover per handler in Proscenium covers only that handler and can hide real bugs.
A test that reaches a panic today aborts the whole test binary with no Ginkgo output, so a recover
would also turn such a regression into an ordinary spec failure.

**Effort:** S
**Priority:** P2
**Depends on:** None (the fork release above is done).

### Contain `@rubygems/` entry paths to the gem root

**What:** In the rubygems `OnLoad` (`internal/plugin/bundless.go`), reject the entry when
`filepath.Rel(gemPath, realPath)` starts with `..`.

**Why:** `filepath.Join(gemPath, RemoveRubygemPrefix(result.Path, gemName))` has no containment
check. An alias target containing `..` builds a file outside every gem root and outside the app
root, and the file's first line can appear in the build error. The Ruby middleware normalises URL
paths before calling Go, but it cannot help here: the `..` is injected inside Go, from config.
Identical before and after the bundless alias fix; found in its review.

**Context:** Check first whether any real alias relies on `..`. `bundler.go` builds the same join.

**Effort:** S
**Priority:** P3
**Depends on:** None

### Guard the unchecked `PluginData` type assertions

**What:** Replace `args.PluginData.(types.PluginData)` with a comma-ok helper at every site:
`bundless.go` (lines 105, 199, 205, 231, 361-362), `bundler.go` (145, 176) and `css.go` (26).
`replacements.go:19` asserts `[]byte`, which is consistent with its own resolver.

**Why:** `bundless.go:361-362` is reachable today. A gem CSS file loaded in the rubygems namespace
has nil `PluginData` (`css.go`'s `OnLoad` supersedes bundless's), so an unresolvable bare `@import`
in it panics with `interface conversion: interface {} is nil`. That one is recovered into a 500 with
an unhelpful message. The `OnLoad` sites are unreachable by construction, but they would abort the
process if they were ever reached.

**Effort:** S
**Priority:** P3
**Depends on:** None (pairs with the recover item above)

### Align how the bundler and bundless plugins handle an alias onto a non-gem path

**What:** `bundless.go` now fails the build with `alias "@rubygems/gem2" maps to "/lib/foo.js", which
is not an @rubygems path`. `bundler.go`'s `resolveRubygemPath` still calls `ResolveRubyGem` on the
aliased path unconditionally and reports `could not resolve Ruby gem "lib"`, which blames the
Gemfile. Gate it on `GemFromSpecifier` the same way.

**Context:** Two related differences. Alias chains follow both hops at import time when bundling,
but only the first when unbundled: the second happens on the browser's request, and needs the
intermediate file to exist in the first gem. And the alias-then-strip-prefixes sequence now exists
in three places (`resolveRubygemPath`, and bundless's top-level and catch-all handlers);
`AUDIT.md` `F-GOUTILS-1` step 2 is the consolidation.

**Effort:** S
**Priority:** P4
**Depends on:** None

## Done

### Cache directory listings for plugin `Resolve` calls (esbuild fork)

Released as `esbuild-internal` `v0.28.2-d551d879` (fork commit `d551d879`, tagged on
`release/0.28.2` of `github.com/joelmoss/esbuild`) and pinned in `go.mod` by `91b50057`. A one-shot
`esbuild.Build()` now reads directories through a caching file system when a plugin calls
`Resolve`; `Context()` is unchanged, because a long-lived context would serve stale listings
between rebuilds. Two tests in the fork's `pkg/api/api_resolve_cache_test.go` pin both halves.

`91b50057`'s message holds the measurements and the one behaviour change: the two largest London
builds went from 149.7ms to 63.2ms (-58%) and from 138.3ms to 67.0ms (-52%) with byte-identical
output, allocations fell from about 1.16M to 0.76M, and a file a plugin creates part-way through a
build is no longer seen by a later `Resolve` if its directory was already listed in that build. The
profile that motivated it: about 46% of a real build in `readdir` and 10% in `lstat`, from about
2,800 directory reads against esbuild's own resolver's 75.
