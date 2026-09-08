# TODOS

## Infrastructure

### Persistent esbuild Context/Rebuild

**What:** Switch `build_to_string`/`resolve` from one-shot `esbuild.Build()` calls to esbuild's persistent `Context()`+`Rebuild()` API so the directory-scan cache survives across calls.

**Why:** Profiling found ~48% of all allocations and 60-90% of CPU in a real build/resolve benchmark come from esbuild-internal re-scanning the same `node_modules` tree from scratch on every single call, because each `Build()` creates a brand-new cache set.

**Context:** Blocked on two open questions: (1) does the Context API support changing `EntryPoints` between `Rebuild()` calls, since Proscenium builds a different entry point per request, and (2) cache invalidation correctness - Proscenium's whole pitch is live on-disk changes reflecting immediately in dev, so a persistent context that caches stale file info would silently break that. Shares root cause (one-shot global state) with the global config refactor - worth scoping together if either is picked up.

**Effort:** L
**Priority:** P3
**Depends on:** None

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

**Why:** `TODOS.md` already records that 60-90% of a build's CPU is esbuild re-scanning
node_modules from scratch per call, so build count is the whole cost. Measured in the dummy app,
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

**Why:** Twelve of them fix something reachable today, not just clarify. The severe one is
`F-GOCSS-2`: `internal/css` encodes end-of-stream three different ways, two loops spin forever on
truncated input, and a nil forwarded to a pointer-receiver `Render()` panics - with no `recover`
behind any of the five cgo exports, so it aborts the host Ruby process rather than failing one
build. `@mixin foo` with no semicolon before EOF is enough.

**Context:** Three themes carry most of the value, and they are why several individually-small
findings are worth landing as a set: the `@rubygems` path rule is re-derived in six places and its
URL spelling in five, with the copies now drifted in four distinguishable ways (`F-GOBUNDLE-1`);
roughly 250 lines of state outlived the refactors meant to remove it, including three
unsynchronised globals the config-threading pass missed (`F-GOPLUGIN-1`, pattern P3); and three
places index an unchecked match behind a guard that checked less (`F-MW-1`, and the two panics
above).

Read `AUDIT.md`'s "AUDIT-THE-AUDIT — pass 4" section before starting anything: it is the final
adjudication and overrides the per-lane priorities earlier in that file. It rejects three
findings, demotes five, and reverses one dependency chain - `F-GOUTILS-1`'s call-site migration
must come *after* `F-GOBUNDLE-1` and `F-GORESOLVE-1`, because both of those delete the sites it
would otherwise migrate. Eleven ordering constraints are listed there; three were undeclared by
the lanes that produced the findings.

Six findings must write the first test for the code they touch - the Chunks, Vendor and
SilenceRequest middleware, `ReactComponentable`, `css_module/path.rb`, `internal/utils`,
`spawnDaemon` and the Rakefile have no coverage at all, and `test/manifest_test.rb` is entirely
commented out. For those, the diff is small and the test is the work.

`F-SIDELOAD-1`'s `NameError` half is already done (`52ad154e`); its `merge_options` extraction and
the write-through-to-shared-state half are still open.

**Effort:** XL in total; individual findings range from one line to a day. The dead-state sweep
(P3) and the `F-GOCSS-1` deletion are the cheapest openers.
**Priority:** P2 for `F-GOCSS-2`, P3 for the rest.
**Depends on:** Nothing external. Internal ordering is in `AUDIT.md` pass 4.
