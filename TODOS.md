# TODOS

## Robustness

### Classify recovered panics by a typed marker, not a text prefix

**What:** `utils.IsPanicMessage` recognises a panic the esbuild fork recovered in a plugin callback
by the `panic:` prefix of the message text. Give the fork's `pluginPanicMsg` a message ID instead
(`logger.MsgID`, surfaced as `Message.ID`) and check that.

**Why:** Free text that happens to start with `panic:` - a CSS parser warning, an alias error built
from a config value - would fail a build that should have externalised a miss. Fail-closed, and
only the developer's own config can produce it, which is why it waited.

**Context:** Raised by the /review adversarial pass on the recover work, 2026-09-20. Needs a new
`MsgID` in the fork's `internal/logger/msg_ids.go` and a fork release (tag, `update.sh`, `go.mod`).
The fork's `api_plugin_panic_test.go` pins the exact text today, and the contract is written at
both ends (`pluginPanicMsg`, `IsPanicMessage`).

**Effort:** S
**Priority:** P4
**Depends on:** None

### Resolve a gem's bare-with-extension imports against the gem when unbundling

**What:** `bundless.go`'s catch-all turns a bare specifier that already has an extension
(`open-props/shadows.css`, `pkg/index.js`) straight into `/node_modules/<specifier>` without
resolving it, so an import from a gem file of a package installed only in that gem's own
`node_modules` points at the app's `node_modules` instead: missing, or a different version, and
the build reports success either way. The extensionless form (`open-props/shadows`) goes through
esbuild and resolves from the gem correctly since the gem-stylesheet fix.

**Why:** Found by the /review outside pass on the recover work, 2026-09-20, as the one gap left in
gem CSS resolution. Pre-existing and shared with gem JavaScript; a resolution-policy change, not
a bug fix, so it was not folded into that branch.

**Context:** The shortcut is the `isBare != "" && hasExt` branch before the resolve ladder. Route
it through `resolveWithEsbuild` when the importer is in the rubygems namespace, and pin it with a
`@import 'open-props/shadows.css'` case beside the existing "gem stylesheet imports" spec.

**Effort:** S
**Priority:** P4
**Depends on:** None

### Key the Bun daemon's build cache on the whole module graph

**What:** `lib/proscenium/runtime/server.rb`'s `cached(path, sourcemap)` keys an entry on
the mtime of the keyed file alone. A bundled build inlines that file's whole import graph - and
bundling is the default - so under `bun test --watch` editing any module a test imports serves the
previous bundle until the test file itself is touched. Unbundled it is narrower but still real: a
CSS module, an SVG and i18n data are inlined either way.

**Why:** A watching suite can pass against bytes the app no longer produces, which is the one
failure mode a test harness must not have. It only bites in `--watch`; a one-shot run builds once,
which is why it was left as a marked shortcut (the `ponytail:` comment on `cached`) rather than
fixed with the daemon.

**Context:** `Metafile: true` is already set in `internal/builder/build.go` and
`build_to_string.go` already unmarshals the metafile to pick an output, so the input list exists
inside Go and is thrown away. The fix is to key on the newest mtime across the metafile's inputs,
which means returning them alongside the code - the same cgo surface question as "One esbuild build
per module, not two", and `op_build` fetches through the middleware stack, which serves code only.
One cheaper fallback if that is too much: key on the newest mtime under the app's source roots,
which is coarse - any edit rebuilds every module - but needs nothing new across the boundary. The
Bun plugin cannot help here; it sees `onResolve` and `onLoad` only, not what the watcher changed.

**Effort:** M
**Priority:** P3
**Depends on:** Nothing, though it shares a boundary change with the source map item.

## Give the two path spaces distinct types

**What:** Named Go types for URL paths and filesystem paths, so the compiler refuses to mix them.

**Why:** The same bug class has surfaced three times, caught by a person every time, never by a test.

1. 2026-02-10, `9da6f14f` through `954b414f`: Windows support added, patched twice as separator
   handling broke in new places, reverted three and a half hours later.
2. 2026-09, `a4d5fa58`: `UrlPathFromFsPath` compared text, so `/app/../outside.css` walked out of a
   root that still looked like a prefix. Raised by CodeRabbit, not by the suite.
3. 2026-09-20, planning issue #73: the proposed Windows fix was one drive-letter-aware absoluteness
   predicate used at every `path.IsAbs`. At `bundler.go:263` the comment reads "Absolute path -
   prepend the root", so that would have produced `C:/app/C:/app/x.js`; at `resolve.go:109` it
   turns a drive path into `.C:/...`.

One root cause each time: both kinds of path are `string`, both are called `path`, and nothing in a
signature says which space a value is in.

**Pros:** The only remedy that makes the mistake impossible rather than merely visible. Conversion
points become named functions, which is where the normalisation and containment rules already want
to live.

**Cons:** esbuild's API is plain `string` on both sides, so every callback boundary needs an
explicit conversion. Go's named string types are weak protection against a careless cast.

**Context:** Declined once, deliberately, in favour of a diagram and a doc comment - the right
trade while the copies are still scattered. `internal/utils/utils.go` is the natural seam:
`UrlPathFromFsPath` is already documented as the one place the rule lives.

**Depends on / blocked by:** Nothing now. `F-GOUTILS-1` step 2's fs-to-URL half landed with the
Windows work, which is what this waited on: the three hand-spelled conversion copies are gone.
Windows also gave the convention a doc comment (TWO PATH SPACES, in `internal/utils/utils.go`), two
named predicates, and three ingress doors, which are the seams types would go on.

**Effort:** L. **Priority:** P3.

## Windows path edge cases the #79 review could not settle

**What:** Four things found in the pre-merge review of PR #79 that need a Windows host, or a
decision, rather than a fix from a Mac.

- **Case.** Roots are compared as exact text everywhere: `bundler.go`'s alias lookup,
  `GemFromFsPath`, `UrlPathFromFsPath`, `Resolver.resolve`, `Manifest.load!`. On Windows
  `filepath.EvalSymlinks` returns the on-disk case and an upper-case drive letter, while Rails.root
  is spelled however Ruby got it. A mismatch skips an alias, or sends a filesystem path out as a
  URL, silently. CI has not hit it; the plan said to decide this on evidence, and there is none
  yet either way.
- **Junctions.** pnpm links with junctions on Windows, and Go 1.23+ `filepath.EvalSymlinks` may no
  longer resolve them. CI checks the fixtures out as git symlinks, so this is untested.
- **`bundler.go`'s alias lookup** trims the root with a bare `strings.TrimPrefix` - the missing
  boundary `rootPathToUrlPath` had. Predates #79, and only misses or mismatches an alias, but it
  belongs with the rest of `F-GOUTILS-1` step 2.
- **`bundless.go`** sends a URL-rooted import with an extension to FINISH, where
  `UrlPathFromFsPath` reads it as a filesystem path: with an app root of `/app`, which is
  Docker's usual WORKDIR, `import "/app/components/x.js"` becomes `/components/x.js`. Predates
  #79; the old `rootPathToUrlPath` did the same.

**Effort:** S each, given a Windows host. **Priority:** P3.

## Simplification audit

### Structural simplifications from the 2026-09-08 and 2026-10-01 audits

**What:** Work through the ranked findings in `docs/AUDIT.md`. The first audit, a whole-repository
read-only audit at commit `5edd7363`, covered the Ruby engine, the Go/esbuild core, the FFI contract between them,
the Bun harness and the browser React manager. 34 accepted findings, each with `file:line`
evidence, a smallest-credible scope, regression risks and the validation it needs. The second, at `65a3857d`, added five more (`F2-`),
seven hygiene deletions and seven bug leads, and re-checked the status of every earlier finding.

**`docs/AUDIT.md` is the record.** Its Progress table carries what is done, which commit did it,
and every correction implementation produced along the way. Read its preamble before starting
anything: the 2026-10-01 "Final priorities and dependencies" was the queue (its last GitHub
issue, #99, is fixed in `2e1e0357` and closed), and the
2026-09-08 "AUDIT-THE-AUDIT — pass 4" still adjudicates that audit's findings, rejecting three,
demoting five and reversing one dependency chain. Do not copy any of that here - two copies drift.

**Next:** none from the audit. #99 (`F-IMPORTER-1`/`-2`), the last audit finding open as a
GitHub issue, is fixed in `2e1e0357` and closed 2026-10-03. On
2026-10-03 the others still open were reviewed for real-world impact and closed as not planned:
#92, #93, #97, #101, #102 (`F-GOUTILS-1` steps 2 and 3, including the alias consolidation and
gem-root containment that used to be written up here), #104 and #105. `docs/AUDIT.md`'s Progress
table lists which findings those were; do not restart them from the audit's write-ups. Nothing
still open misserves or crashes on a client-supplied URL - the two that did, the double-decode
`F2-MW-1` (`e104e277`), and the two `internal/css` defects before them, are fixed.

**File path to URL path is done.** `utils.UrlPathFromFsPath` is the only
spelling: `resolve.go` and `plugin/css.go` since `8452092a`, and `dirname.go`, `bundler.go` and
`bundless.go` since the Windows work on PR #79, which deleted `rootPathToUrlPath` and
with it the missing boundary - root `/app` no longer claims `/app-other/x.css`.
`test/dirname_boundary_test.go` pins that, and fails against both naive migrations.

**Still open from the Codex adversarial pass** (`docs/AUDIT.md`, "CODEX ADVERSARIAL PASS"). One item
left: finding 2, vendor's `immutable, max-age=100.years` on an unversioned URL. It is a one-header
decision - drop `immutable` and shorten `max-age` so `Last-Modified` revalidates, or record it as
accepted. Do not leave it open. Findings 9 and 10 are fixed in `407921ba` and finding 3 is recorded
won't-fix there; the reasoning, including the measurements that rejected a per-root load lock, is
in `docs/AUDIT.md`'s table rather than repeated here.

**Worth keeping from the middleware fixes:** normalise a request path once, then route, check and
build from that single value. Three separate defects were the same shape - `Chunks` reading a raw
path the file handler later normalised, and `find_type` / `file_readable?` / `path_to_build`
disagreeing three ways.

**Effort:** XL in total; individual findings range from one line to a day.
**Priority:** P3 for what remains. One bug lead came out of `F-GOBUNDLE-1` and is recorded in
`docs/AUDIT.md` rather than fixed: an extensionless `@rubygems/` specifier that esbuild cannot resolve
leaks an absolute filesystem path into the built output, because the top-level handler returns
without passing through the catch-all's URL-conversion tail.
**Depends on:** Nothing external. Internal ordering is in `docs/AUDIT.md`, 2026-10-01 "Final priorities and dependencies".

## Frontend

### An SVG imported from JSX should follow its tsconfig's JSX runtime

**What:** Stamp `/** @jsxImportSource X */` into the component `internal/plugin/svg.go` generates
for an SVG imported from JSX, with X read from the `tsconfig.json`/`jsconfig.json` nearest the SVG.

**Why:** The generated component is plain JSX, but esbuild compiles it with its default runtime,
React, whatever the app's tsconfig says: tsconfig only applies to files esbuild reads itself, not
to a plugin's contents, in the `svgFromJsx` namespace or the `file` one (measured 2026-10-03). So
a Preact app that imports an SVG from JSX bundles React for it. A stamped pragma does work.

**Context:** Deferred until a non-React app imports SVGs from JSX; every current one is React. The
policy is settled: the tsconfig nearest the SVG decides, so one module per SVG, and a pragma in the
importing file does not reach it. esbuild-internal's `resolver/tsconfig_json.go` already parses
tsconfig (comments and all) and reads `jsxImportSource`.

**Priority:** P4

### One esbuild build per module, not two

**What:** Return a module's source map from the same `esbuild.Build()` that produced its code,
instead of rebuilding. Today `internal/builder/build.go` strips a `.map` suffix from the entry
point and runs a complete independent build, so any module whose map is fetched costs two full
builds.

**Mostly handled.** `SourcemapInline` embeds the map in the code, so one build returns both, and
the Bun daemon uses it for every module it builds. What is left is the case where the map has to
be a separate file: a browser in development with devtools open, which fetches `<path>.map` after
the code, and the unbundled Bun path, where each module is served rather than built.

**Why:** Build count is most of the cost, because most of a build is esbuild reading and resolving
files rather than transforming them (the profile is in the Done section below). The one-vs-two
measurements that put this at P2 predate the directory-listing cache, which cut the big builds by
about half, and what remains is development-only with devtools open. Re-measure before doing it.

**Context:** esbuild already emits both output files from one call (`Sourcemap: SourceMapExternal`),
and `build_to_string.go` already contains the logic to pick one of two output files by suffix - so
the build is being thrown away rather than being unavailable. The fix needs a way to ask for both
at once, which means the cgo surface in `main.go` and its mirror in `lib/proscenium/builder.rb`
(AGENTS.md flags that pairing). The daemon would then cache the pair under one key.
`register({ sourcemaps: false })` in `lib/proscenium/runtime/bun.js` skips what remains, at the
cost of readable failures in a minified build. Bun does not apply the harness's maps at all; the
README's `bun test` section records that.

**Effort:** M
**Priority:** P3 (was P2)
**Depends on:** A post-cache measurement of the separate-map case.

### Node, Vitest and Deno test adapters

**What:** Adapters so `node --test`, Vitest and Deno can run app JavaScript, driving the same
daemon protocol as the Bun plugin (`lib/proscenium/runtime/server.rb`).

**Why:** Issue #65 asked for "Bun, Deno or Node" and is closed with Bun shipped. Nobody is asking
for the rest. The item stays only because the constraints below were expensive to establish. The
daemon is mostly runtime-agnostic, but not entirely: `op_handshake` hands every client the Bun
plugin's path, and `RUNTIME_MODULES` adds Bun's own module namespaces to the entry build's
externals. An adapter is a new plugin file plus letting the client say which runtime is asking.

**Context:** Node's `resolve` hook sees extensionless and bare specifiers directly, so the Node
adapter is *simpler* than Bun's - but it must use async `module.register`, not the synchronous
`module.registerHooks`, which cannot await the daemon. Node also rejects unknown import attributes
at parse time (`ERR_IMPORT_ATTRIBUTE_UNSUPPORTED`), so every file has to go through the load hook
for `with { unbundle: 'true' }` to survive. Deno has no load hook at all, so it can only ever do
resolution - no CSS modules, SVG components or i18n.

**Effort:** M
**Priority:** P4 (was P3)
**Depends on:** Someone asking.

## Infrastructure

### Verify the platform-less gem before publishing

**What:** A release verify leg that resolves to the platform-less gem and asserts
`Proscenium::Builder::UnsupportedPlatform`. Every platform gem is now installed and loaded before
publishing - Linux in containers, Windows and both darwin archs natively - but no leg resolves to
the plain gem, because on each of them a platform gem wins.

**Why:** The plain gem is what an unsupported host installs, and what it has to do there is raise
the named error rather than an FFI `LoadError`. `test/packaging_test.rb` asserts that against a
temp copy of `lib/`, not against the published archive.

**Context:** The plain gem is not unguarded today: `build-plain` builds in a job that has never
compiled and then fails on any `lib/proscenium/ext/` entry in the archive. That catches the 0.25.2
defect. What is missing is the other half. The leg needs a host matching no platform gem, so a
musl image is the cheap way to get one, and it cannot use `bin/verify-installed-gem` as it stands:
that script expects a platform and a library that loads.

**Effort:** S. **Priority:** P3.

### Skip the extension-finding `Resolve` in the Bundler plugin

**What:** 58 of the distinct specifiers app-b's `appointment/create/component.jsx` sends to
`build.Resolve` are relative or absolute paths with no extension, and the Bundler plugin calls
`Resolve` for them only to find the extension before it applies aliases and gem URL mapping.
Avoiding that call means doing that work in Proscenium, or letting esbuild resolve them and
applying aliases afterwards.

**Why:** It is the lever left over after the directory-listing cache took the easy half. The cache
made each of those calls cheap; this removes them. Nobody has measured what they cost now.

**Context:** Riskier than the cache, because it moves resolution logic across the esbuild boundary
rather than making the existing calls faster. Also tried and rejected on the way to the cache: a
process-wide directory cache validated by each directory's `ModKey` (mtime, with esbuild's 3 second
racy-timestamp gap). About -50% on the big builds, no better than the per-build cache, and it adds
staleness risk across builds.

**Next:** Profile one big app-b build post-cache and read off the time under those 58 `Resolve`
calls. Under about 10% of the build, delete this item.

**Effort:** M
**Priority:** P3
**Depends on:** That measurement.

### Persistent esbuild Context/Rebuild

**What:** Switch `build_to_string`/`resolve` from one-shot `esbuild.Build()` calls to esbuild's
persistent `Context()`+`Rebuild()` API so that parsed files and file contents survive across calls.

**Why:** What survives a `Rebuild()` is the `CacheSet`: file contents (revalidated with `ModKey` on
every read), parsed JS, CSS and JSON, and source indexes. Directory listings do not: `contextImpl`
creates its file system with `DoNotCache: true` and `rebuildImpl` makes a new `realFS` per rebuild,
and directory reads are where most of a real build went. Nobody has measured what the surviving
parse and read work is worth.

**Context:** `EntryPoints` cannot change between `Rebuild()` calls: `contextImpl` validates the
options once and captures the entry points in `rebuildArgs`, so it would take one Context per
entry point and per config, and Proscenium builds a different entry point per request, so the
memory cost of holding them is unknown. File-content invalidation is safe: `FSCache` stats on every
read and re-reads when the `ModKey` differs, distrusting an mtime within 3 seconds of now.

**Next:** Time an unchanged-entry `Rebuild()` against a fresh `Build()` on one big app-b entry.
Under about 10%, delete this item.

**Effort:** L
**Priority:** P4
**Depends on:** That measurement.

## Package manager (#154)

### Regenerate dependency contexts from a Bundler `after-install-all` hook

**What:** Ship a Bundler plugin that hooks `Bundler::Plugin::Events::GEM_AFTER_INSTALL_ALL` and
regenerates `.proscenium/packages/<gem>/package.json` after every `bundle install`, so a Gemfile
change never leaves contexts stale even when nobody runs `proscenium install`.

**Why:** The plan's orchestrator exists largely to keep contexts in step with Gemfile.lock. A
Bundler hook does that at the moment the Ruby graph changes, with no wrapper command.

**Context:** Deferred by the 2026-10-03 /autoplan CEO review of `docs/plans/154-package-manager.md`,
behind the open question of whether an orchestrator is needed at all (the CLI became Ruby, running under `bundle exec`, at the 2026-10-04 gate). Plugins need a `plugin`
line in the app's Gemfile, which is a manifest edit the plan has to own. Stage A went GO
(2026-10-04) with `install` as the only orchestrator, so this is now a choice on evidence: add it
if the migrated apps keep shipping stale contexts.

**Effort:** M (human) / S (CC)
**Priority:** P3
**Depends on:** #154 v1 in use by the migrated apps

### A build that starts just before an install can read a half-written tree

**What:** `ContextMap.installing?` holds its shared lock on `.proscenium/lock` only for the probe,
so a build or resolve that passes the probe an instant before `proscenium install` takes the lock
runs while the install rewrites contexts and `node_modules`.

**Why:** That one build can come from a half-installed tree. The next build sees the marker and
refuses, so it corrects itself, but the refusal is not airtight.

**Context:** Raised by Codex on #168 and left by decision: holding the shared lock through every
build would make each install wait on whatever is building, and the CLI waits only about a
second before PSM-E-BUSY, so installs beside a busy dev server would fail (C34: the probe "never
stops an install starting"). A fix that keeps C34 would have the build check the marker or the
lock's generation again after it finishes, and retry or refuse.

**Effort:** S (human) / S (CC)
**Priority:** P4
**Depends on:** nothing

### One URL for an app's own package that a gem also peers on

**What:** An app's `link:`, `file:` or workspace package keeps its `/node_modules/<name>/` URL
(`AppLocalPackages`), while a participating gem that declares the same package as a peer reaches
it through its context and gets its real path's URL.

**Why:** Unbundled, the browser loads that package twice, so its singleton state splits.
`Verify#check_peers` passes the setup, because both links have the same real path.

**Context:** Raised by Codex on #168. It needs a choice about which URL wins: keep the app's link
URL for the gem too (map the gem-side resolution back to the app's link when its real path is an
app-local package's), or drop the exemption for a package a gem shares.

**Effort:** S (human) / S (CC)
**Priority:** P3

### Serve gem contexts from a bundle root outside the Rails app

**What:** Contexts live at `Bundler.root`. When that is outside `Rails.root`, as in a monorepo whose
Gemfile sits above the Rails app, nothing under them has a URL: `internal/resolver/resolve.go`
refuses a gem dependency as resolved outside the app root, and unbundled pages cannot load one.

**Why:** Bundled builds would work, but resolution and unbundled serving do not, so for now the
engine refuses an adopted app laid out this way (`Builder.outside_rails_root`), with a message
naming both directories (#168, Codex review).

**Context:** Support means a second served root: `UrlPathFromFsPath` and the middleware's
allow-list taking the bundle root's `.proscenium/packages/` and its store, with the same
containment rules as `node_modules`.

**Effort:** M (human) / S (CC)
**Priority:** P3

### Serve unbundled packages from a store outside the app root

**What:** With pnpm's global virtual store, or any layout whose real files sit outside the app
root, an unbundled package's own imports resolve to real paths with no URL, and come out as
absolute file system paths (`/private/var/.../scheduler/index.js`) the browser cannot load.

**Why:** It predates #154: probed with no gem contexts at all, an unbundled `react-dom` from such a
store imports `scheduler` by its file system path. Only the shared-peer case is handled today:
`ContextRealPath` gives a context's link the app's link URL when both reach the same file outside
the root (#168), so a gem and the app still load React once.

**Context:** Supporting it means serving through the links rather than the real paths for anything
under an external store, and resolving a package's dependencies from its link spelling. Until
then, an app that unbundles packages needs its store inside the app root.

**Effort:** M (human) / S (CC)
**Priority:** P3
**Depends on:** nothing

### `proscenium inspect --why <js-package>`

**What:** Name which gem contexts (and the app) declare a given JS package, with each declared range.

**Why:** Once several gems contribute dependencies, "why is this package installed" has no native
answer that maps back to gems.

**Context:** Deferred by the 2026-10-03 /autoplan CEO review of #154 as outside the minimum scope.
Builds on `inspect`'s existing per-gem projection.

**Effort:** S (human) / S (CC)
**Priority:** P4
**Depends on:** #154 `proscenium inspect`

### npm adapter for RubyGem NPM dependencies

**What:** Add npm (10.9.x, 11.x, 12.x lines) as a qualified adapter: its `*` local-link rule, hoisted layout, nested copies under contexts, `npm ci` frozen path and conformance rows.

**Why:** v1 ships pnpm and Bun only (user decision at the 2026-10-04 /autoplan gate, UC1); npm is the default manager for many fresh Rails apps and outside authors.

**Context:** The plan's npm evidence so far is synthetic: the version, fresh-checkout and layout probes kept in the "Measured evidence" section of `docs/plans/154-package-manager.md`. Until this lands, npm projects get the unsupported-manager error. Start from those probes; the conformance matrix will need npm rows of its own.

**Effort:** L (human) / M (CC)
**Priority:** P3
**Depends on:** a real npm user (the pnpm and Bun pilot went GO on 2026-10-04)

### Deferred package manager commands

**What:** Decide, one by one, whether to add `init`, `sync`, `lock`, `update`, `add`/`remove`, `migrate`, `clean`, a committed `bin/proscenium` launcher with version handoff, transactional journals and the 100-gem performance gate.

**Why:** v1 ships only `install`, `install --frozen`, `inspect` (also `doctor`) and `gem check` (UC2, 2026-10-04). Each deferred piece is another contract with native tools; add one only when a user hits the need.

**Context:** The original contracts were folded out of the plan body on 2026-10-04; they survive in the plan's git history (before that fold) and in its Review record. The three app migrations use a written recipe instead of `migrate`.

**Effort:** M per command (human) / S (CC)
**Priority:** P4
**Depends on:** #154 v1 in use by app-b, app-a and app-c

### Manager-independent dependency URLs

**What:** Design a dependency URL scheme that does not change when the package manager or its hoisting changes, with an identity that covers source and patch provenance (Git revision, tarball, patch) and the copy's dependency environment, plus precompiled-manifest invalidation and a deploy test.

**Why:** Moved out of #154 v1 (UC3, 2026-10-04). v1 keeps real-path URLs, which still carry `.pnpm`/`.bun` segments and change if an app switches manager.

**Context:** The rejected first draft (name, version, path, peer digest) collides for Git, tarball and patched copies of the same version (Eng review, Codex). Open as its own GitHub issue when picked up.

**Effort:** L (human) / M (CC)
**Priority:** P4
**Depends on:** #154 v1

### Context name override for gems with invalid npm names

**What:** Let the app's package.json rename a gem's dependency context (`proscenium.gemOverrides.<gem>.name`) so a gem whose name is not a valid npm package name, such as one with uppercase letters, can participate.

**Why:** v1 gives such a gem a participation error instead. The override was cut in the 2026-10-04 /autoplan Eng pass because no known gem needs it and a renamed context would sit outside the `@rubygems/*` alias and lock-scan protections.

**Context:** If added, apply the cross-gem reference rules, `npm:` alias normalization and the post-install lock scan to the full participating name map, overridden names included, with a request-logging fixture proving an overridden name never reaches a registry.

**Effort:** S (human) / S (CC)
**Priority:** P4
**Depends on:** a real gem with a non-npm-valid name opting in

## Done

### Map gem paths to `@rubygems/` without a regex (#95)

`resolver.rb` built a regex from a gem path without escaping it, so a gem path holding `+` was
left unmapped and an unbalanced `(` raised `RegexpError`. `BundledGems.virtual_path` is now the one
rule, a plain prefix match that `Resolver` and `Manifest` share, and it takes the longest root as
Go's `GemFromFsPath` does, so a file under a nested gem gets one URL from both sides. Moved here
from the #79 Windows list; `docs/AUDIT.md`'s F-BOOT-1 row has the detail.

### Cache directory listings for plugin `Resolve` calls (esbuild fork)

Released as `esbuild-internal` `v0.28.2-d551d879` (fork commit `d551d879`, tagged on
`release/0.28.2` of `github.com/joelmoss/esbuild`) and pinned in `go.mod` by `91b50057`. A one-shot
`esbuild.Build()` now reads directories through a caching file system when a plugin calls
`Resolve`; `Context()` is unchanged, because a long-lived context would serve stale listings
between rebuilds. Two tests in the fork's `pkg/api/api_resolve_cache_test.go` (`../esbuild`;
`api/` in the generated `esbuild-internal`) pin both halves.

`91b50057`'s message holds the measurements and the one behaviour change: the two largest app-b
builds went from 149.7ms to 63.2ms (-58%) and from 138.3ms to 67.0ms (-52%) with byte-identical
output, allocations fell from about 1.16M to 0.76M, and a file a plugin creates part-way through a
build is no longer seen by a later `Resolve` if its directory was already listed in that build. The
profile that motivated it: about 46% of a real build in `readdir` and 10% in `lstat`, from about
2,800 directory reads against esbuild's own resolver's 75.

### Recover from panics in esbuild plugin callbacks (esbuild fork)

Released as `esbuild-internal` `v0.28.2-7db68371` (fork commit `7db68371` on `release/0.28.2`)
and pinned in `go.mod`. Each plugin callback wrapper in the fork's `pkg/api/api_impl.go`
(`../esbuild`; `api/api_impl.go` in the generated `esbuild-internal`) recovers into a build
error, `panic: <value> (in OnLoad callback)` with the stack in a note, the shape `parseFile`'s own
recover uses; five fork tests pin every callback type, the nested `build.Resolve` path, and a
following build succeeding. The OnLoad one aborted the test binary before the change. Not covered, on either side: esbuild's own internal goroutines (the linker's
chunk, source-map and renaming workers), so a panic inside esbuild itself still takes the process
down.

On this side: `utils.Recover` wraps `BuildToString`, `Resolve` and `Compile` for the calling
goroutine (`test/panic_test.go`, where a nil config is the injection); `utils.HasPanicMessage`
keeps a nested-resolve panic from being externalised as a miss in both `resolveWithEsbuild`
closures; `types.PluginDataOf` replaced the nine bare `PluginData` assertions; and the one
reachable panic's root cause is fixed rather than guarded - `css.go` returned gem CSS without the
`ResolveDir` and gem root bundless had attached (esbuild drops a loader result with no contents),
so unbundled gem stylesheets can now `@import` their own `node_modules` and their siblings
(`test/rubygems_test.go`, "gem stylesheet imports"). Two more from the outside review: the nested
CSS-module build returns its structured errors, so the location is the CSS line rather than the JS
importer; and `Builder#compile` raises `CompileError` with esbuild's messages instead of
returning `false` and discarding them. `BuildError` prints notes, so a stack reaches the error
page. Plan and review record:
`~/.gstack/projects/joelmoss-proscenium/joelmoss-master-recover-panics-plan-20260920.md`.

### Full concurrency audit of esbuild-internal

Dropped. Its prerequisite, the global config refactor's Phase 4, landed in `768021ee` with
`test/phase4_esbuild_concurrency_test.go`, which exercises the only surface Proscenium calls
concurrently (`Build`, `Resolve`) across independent roots. A general audit of the rest of the
fork was XL with no trigger; reopen if something outside that surface is ever called concurrently.
