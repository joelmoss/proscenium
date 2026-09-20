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

**What:** `lib/proscenium/runtime/server.rb`'s `cached(:build, path, sourcemap)` keys an entry on
the mtime of the keyed file alone. A bundled build inlines that file's whole import graph - and
bundling is the default - so under `bun test --watch` editing any module a test imports serves the
previous bundle until the test file itself is touched. Unbundled it is narrower but still real: a
CSS module, an SVG and i18n data are inlined either way.

**Why:** A watching suite can pass against bytes the app no longer produces, which is the one
failure mode a test harness must not have. It only bites in `--watch`; a one-shot run builds once,
which is why it was left as a marked shortcut (`server.rb:470`) rather than fixed with the daemon.

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

### Judge output directory containment after resolving symlinks

**What:** `builder.OutputDirUnderRoot` (`internal/builder/compile.go`) compares root and target
lexically with `filepath.Rel`, so a symlinked directory *component* in `OutputDir` escapes it: with
`public` a symlink to `/etc`, `public/assets` passes the check and the `os.RemoveAll` below it
deletes `/etc/assets`. Resolving the link itself is not the hole - `RemoveAll` unlinks a symlink
rather than following it - only an intermediate component is.

**Why:** Completes the containment work of `da4c285a`, `4f2983a7` and `ebfb2b78`, which closed the
empty, `..` and absolute cases. Unlike the two items above this one is destructive rather than
fail-closed - it deletes outside the root rather than failing a build that should pass - but it is
reachable only through the developer's own `output_dir` against their own directory layout, and a
symlinked `public` is unusual, which is why it is not urgent.

**Context:** `filepath.EvalSymlinks` on both root and target before `Rel`, with the target's parent
resolved when the target does not exist yet (the first compile), and `os.RemoveAll` then taking the
resolved path rather than the lexical one. The plugins already do this for resolve dirs
(`bundless.go:84`, `bundler.go:316`). `test/compile_test.go`'s table drives `OutputDirUnderRoot`
directly, so the case is one entry plus a symlink the spec creates in a tempdir - not one checked
into `fixtures/`, where it would not survive every platform and git config.

**Effort:** S
**Priority:** P4
**Depends on:** None

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

**Depends on / blocked by:** `F-GOUTILS-1` step 2 below. Do that first, so there are three fewer
conversion sites to type.

**Effort:** L. **Priority:** P3.

## Finish Windows support

**What:** The path work behind issue #73. A CI probe (draft PR #79) already answered whether it is
worth doing.

**Why:** Windows is not blocked. The probe confirmed on `windows-latest` that the compiled DLL
loads through Ruby FFI, that the 24 tracked fixture symlinks survive checkout given
`core.symlinks`, `core.longpaths` and a `symlink=dir` attribute, and that the esbuild fork hands
back OS-form paths. `go test` there runs 480 specs: 313 pass, 167 fail, all on one signature -
`Plugin "bundler" returned a non-absolute path: fixtures\dummy\vendor\gem1\...`. Backslashes,
and relative where the code assumed absolute.

**Context:** The design is two predicates classified per call site, not one smarter predicate
swapped in everywhere - that blanket swap is the February mistake inverted, and would break
`bundler.go:263` and `resolve.go:109`. Slash-form internally with normalisation at the esbuild
boundary, but keep `filepath` behind named helpers for genuine filesystem construction: `path.Join`
collapses `//server/share` and does not understand drive roots. Note `css.go` hashes `args.Path`
for CSS module class names and Ruby mirrors that hash, so changing the form of those paths changes
user-visible class names silently.

**Blocked by, but not on Proscenium:** `bin/test` cannot run on Windows because sqlite3's
precompiled `x64-mingw-ucrt` gem fails to load with `127: The specified procedure could not be
found`. Not the Ruby version - 3.3.12 fails identically, so sqlite3-ruby#628 does not describe it -
and not a malformed artifact: its PE imports are 90 standard Ruby C API symbols against the correct
DLL per ABI directory. The dummy app needs ActiveRecord, so the suite cannot boot. `go test` and
the FFI-load CI step are the Windows coverage until this is solved.

**Effort:** L. **Priority:** P3.

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

**Next:** `F-GOUTILS-1`'s step 2, then step 3. `F-GORESOLVE-1` landed in `8452092a`, so all three
`@rubygems` consumers are done (pass 4 ruling 1, consumers-by-deletion first). Nothing still
open misserves or crashes on a client-supplied URL - the two that did, and the two `internal/css`
defects before them, are fixed. What remains is materiality rather than breakage. Several findings
must write the first test for the code they touch; `AUDIT.md`'s pattern P7 lists which, and for
those the diff is small and the test is the work.

**Step 2 absorbs two items that used to stand alone here.** The alias-then-strip-prefixes-then-join
sequence still exists in the two plugins (`bundler.go:136`, `bundless.go:160`; `resolve.go`'s
copies went with `F-GORESOLVE-1`), and step 2 is the consolidation, so both land there as one
function with one check. (1) Align how the two plugins treat an alias onto a non-gem path:
`bundless.go` fails the build with `alias "@rubygems/gem2" maps to "/lib/foo.js", which is not an
@rubygems path`, while `bundler.go`'s `resolveRubygemPath` calls `ResolveRubyGem` unconditionally
and reports `could not resolve Ruby gem "lib"`, which blames the Gemfile; gate it on
`GemFromSpecifier` the same way. (2) Contain the path to the gem root. `GemFromSpecifier` does
this now (`8452092a`: the suffix is cleaned as a relative path, and one that escapes is an error
naming the specifier and the gem), and `resolve.go` acts on it - but neither plugin does, for any
`@rubygems/` import, aliased or not. `bundler.go`'s `resolveRubygemPath` (`:90`, `:136`) and
`bundless.go`'s entry-point join (`:160`) never call `GemFromSpecifier`; they join the raw suffix
onto the gem root, so `import "@rubygems/gem2/../../x.json"` in a bundled graph reads outside the
gem. The alias branches (`bundler.go:221`, `bundless.go:131`) call it and discard the error. Not a
new read capability - esbuild resolves a plain `../../x.json` from any dependency with no root
check either - but the rule should hold everywhere it is spelled. Two `resolve.go` exits are in
the same state: the absolute-path exit and the non-gem esbuild exit join the specifier onto the
root with no under-a-root check (`/../../etc/x.css` joins outside it; the URL goes back as
written), while the relative branch now refuses. One `UrlPathFromFsPath` check on each closes
them; fold that in here. No fixture alias uses `..`. Also from that review: alias chains follow
both hops at import time when bundling, but only the first when unbundled - the second happens
on the browser's request, and needs the intermediate file to exist in the first gem.

**The other direction, file path to URL path, has one home now.** `utils.UrlPathFromFsPath`
(`8452092a`) answers it for `resolve.go` and `plugin/css.go`, gem roots first, then the app root
matched at a "/" boundary. Three copies remain: `dirname.go:32`, and `bundler.go:356` /
`bundless.go:406` through `rootPathToUrlPath` (`bundless.go:427`), which has no boundary - root
`/app` claims `/app-other/x.css`, the hole `8284d26c` closed for gem roots. Step 2 moves those
three to the helper and deletes `rootPathToUrlPath`. The plugins need the "leave the path
unchanged" arm when neither root matches, which is why they did not move with the first two.

**Still open from the Codex adversarial pass** (`AUDIT.md`, "CODEX ADVERSARIAL PASS"). One item
left: finding 2, vendor's `immutable, max-age=100.years` on an unversioned URL. It is a one-header
decision - drop `immutable` and shorten `max-age` so `Last-Modified` revalidates, or record it as
accepted. Do not leave it open. Findings 9 and 10 are fixed in `407921ba` and finding 3 is recorded
won't-fix there; the reasoning, including the measurements that rejected a per-root load lock, is
in `AUDIT.md`'s table rather than repeated here.

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

**Why:** Build count is most of the cost, because most of a build is esbuild reading and resolving
files rather than transforming them (the profile is in the Done section below). The one-vs-two
measurements that put this at P2 predate the directory-listing cache, which cut the big builds by
about half, and what remains is development-only with devtools open. Re-measure before doing it.

**Context:** esbuild already emits both output files from one call (`Sourcemap: SourceMapExternal`),
and `build_to_string.go` already contains the logic to pick one of two output files by suffix - so
the build is being thrown away rather than being unavailable. The fix needs a way to ask for both
at once, which means the cgo surface in `main.go` and its mirror in `lib/proscenium/builder.rb`
(CLAUDE.md flags that pairing). The daemon would then cache the pair under one key.
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

### Verify the darwin and platform-less gems before publishing

**What:** The release workflow's `verify` job installs from a generated index and loads the
library, but only on `x86_64-linux-gnu` and `aarch64-linux-gnu`. Add a macOS leg for the two darwin
gems, and a leg that resolves to the platform-less gem and asserts
`Proscenium::Builder::UnsupportedPlatform`.

**Why:** Those two archives are published on the strength of having been built, not of having been
installed. A darwin gem that will not `dlopen` - wrong minimum macOS version, a CGO flag that
changed - reaches RubyGems and is found by the first person to `bundle install`, which is the
failure this whole job exists to prevent for Linux.

**Context:** The plain gem is not unguarded today: `build-plain` builds in a job that has never
compiled and then fails on any `lib/proscenium/ext/` entry in the archive. That catches the 0.25.2
defect. What is missing is the other half - that the gem an unsupported host actually resolves to
raises the named error rather than an FFI `LoadError`. `test/packaging_test.rb` asserts that
against a temp copy of `lib/`, not against the published archive. The darwin leg needs
`macos-latest` runners, which the build jobs already use; the plain-gem leg needs an image matching
no platform gem, so a musl image is the cheap way to get one.

**Effort:** S. **Priority:** P2.

### Skip the extension-finding `Resolve` in the Bundler plugin

**What:** 58 of the distinct specifiers London's `appointment/create/component.jsx` sends to
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

**Next:** Profile one big London build post-cache and read off the time under those 58 `Resolve`
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

**Next:** Time an unchanged-entry `Rebuild()` against a fresh `Build()` on one big London entry.
Under about 10%, delete this item.

**Effort:** L
**Priority:** P4
**Depends on:** That measurement.

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

### Recover from panics in esbuild plugin callbacks (esbuild fork)

Released as `esbuild-internal` `v0.28.2-7db68371` (fork commit `7db68371` on `release/0.28.2`)
and pinned in `go.mod`. Each plugin callback wrapper in the fork's `pkg/api/api_impl.go` recovers
into a build error, `panic: <value> (in OnLoad callback)` with the stack in a note, the shape
`parseFile`'s own recover uses; five fork tests pin every callback type, the nested
`build.Resolve` path, and a following build succeeding. The OnLoad one aborted the test binary
before the change. Not covered, on either side: esbuild's own internal goroutines (the linker's
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
