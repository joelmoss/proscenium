# Expand OS support: Linux musl and Windows x64

## Status, 2026-09-22

Written 2026-09-20 as the implementation plan for issue #73, and kept as the record of why things
are the way they are. Everything after this section is the plan as written, and is not updated:
where it disagrees with this section - the `bun test` harness being Unix-only, "no unresolved
decisions" - this section is current. Line numbers below are as of then.

| Part | State |
|---|---|
| PR 1, release workflow and artifact verification | **Done.** `.github/workflows/release.yml`; see CLAUDE.md's Releasing section. |
| PR 2, `-gnu` rename and plain gem | **Done.** |
| PR 2, musl gems | **Dropped.** Go's c-shared libraries cannot be `dlopen`ed on musl ([golang/go#54805](https://github.com/golang/go/issues/54805)). See CLAUDE.md. |
| PR 3 Phase 1, Windows probe | **Done, GO.** Draft PR #79. |
| PR 3 Phase 2a, fs-to-URL copies onto `UrlPathFromFsPath` | **Done**, with the boundary regression test (`test/dirname_boundary_test.go`). |
| PR 3 Phase 2b, one path convention | **Done**, except items 1 and 6 as written: each of the three `build.Resolve` sites normalises its own result rather than going through one wrapper, and there is no `forbidigo` rule. |
| PR 3 Phase 3, fixtures | **Done.** The symlinks survive with `core.symlinks`; `core.autocrlf false` turned out to matter too. |
| PR 3 Phase 4, packaging | **Open.** See "Ship a Windows gem" in TODOS.md. |
| PR 3 Phase 5, docs | **Open.** README's platform table does not list Windows yet. |

**Scope changed after writing:** the `bun test` harness runs on Windows. It was ruled out below on
the assumption that its unix socket would not work there; a CI probe showed Windows Ruby's
`UNIXServer` and Bun's `Bun.connect({ unix })` both do, and what was actually wrong was two path
conversions and a hardcoded `/tmp`.

**Two of the plan's NO-GO triggers fired and were fixed rather than accepted.** The esbuild fork
did need changes - `CssLocalHash` hashing a separator-independent path, and the metafile quoting
paths it had substituted into already-quoted JSON strings - both in `joelmoss/esbuild`.

**Not anticipated here at all:** sqlite3's precompiled Windows gem failing to load on Ruby 3.4.5+
(`clock_gettime` moved out of the Ruby DLL; fixed in sqlite3 2.8.1), and ffi's `FreeLibrary` on
the Go library crashing the interpreter at exit (fixed by pinning the module in `builder.rb`).

Issue: https://github.com/joelmoss/proscenium/issues/73
Base: cut a new branch from `master`. `workroom/ruby-ridge` is superseded — `git cherry -v master
HEAD` shows one commit already landed, and the other landed as `c37363b0` plus two review-driven
follow-ups. Nothing here depends on either.

## Context

Proscenium ships four platform gems: `x86_64-darwin`, `arm64-darwin`, `x86_64-linux`,
`aarch64-linux`. Two gaps.

**Alpine users are broken today, and not in the way first assumed.** RubyGems documents that a bare
Linux platform name matches both glibc and musl, so an Alpine host does not fall through to the
plain gem. It installs `x86_64-linux`, which carries a glibc shared library, and fails when FFI
loads it. Publishing a musl gem does not fix that, because the bare name keeps matching. The rule
that fixes it is that a `-gnu` binary is never selected on musl, so the existing gems have to be
renamed. Nokogiri made this move.

**Windows was attempted and abandoned.** Four commits on 2026-02-10:

| commit | time | what |
|---|---|---|
| `9da6f14f` | 09:28 | add `x64-mingw-ucrt`, windows-latest CI, ~15 `path.Join` → `filepath.Join` |
| `4c6c6fe0` | 11:09 | add `utils.PathIsAbsolute`, because `filepath.IsAbs("/lib/foo")` is false on Windows |
| `301ea4dd` | 12:18 | sprinkle `filepath.ToSlash` across seven more files |
| `954b414f` | 12:53 | remove Windows support |

Blanket replacement, then site-by-site patching, then revert. The codebase mixes two path spaces
and no commit named which space each variable was in.

**This is a recurring bug class, not a Windows problem.** `a4d5fa58`, this month: `UrlPathFromFsPath`
compared text, so `/app/../outside.css` walked out of a root that still looked like a prefix. Caught
in review, not by a test. And during this plan's own review, the first proposed remedy — one smarter
absoluteness predicate used everywhere — would have produced `C:/app/C:/app/x.js` at
`bundler.go:263`. Three instances, one root cause: both kinds of path are `string`, both are called
`path`, nothing distinguishes them.

Scope: **Linux musl (x86_64 + aarch64) and Windows x64**, delivering platform gems plus green
`go test ./test` and `bin/test` on Windows. The `bun test` harness stays Unix-only; its daemon binds
a `UNIXServer` on a socket under `/tmp`. Windows arm64 and FreeBSD are out.

## Three PRs

```
PR 1  Release workflow + artifact verification  ──┐
PR 2  musl gems, -gnu rename, plain gem         ──┤ PR 3 is independent of both
PR 3  Windows ── Phase 1 probe ──── GO/NO-GO ─────┴── Phases 2-5
```

The musl half is packaging with no Go source changes. The Windows half is roughly thirteen files
and was abandoned once. PR 3's decision point is real: **NO-GO is an acceptable outcome**, costing
one CI run.

---

## PR 1: release pipeline and artifact verification

Releases are hand-run. `proscenium.gemspec:19` sets `rubygems_mfa_required` and `Rakefile:48` pushes
each gem in turn, so RubyGems asks for a one-time code per push — five now, seven after PR 2, eight
after PR 3. `Rakefile:96-98` records a partial publish already happening.

- Tag-triggered GitHub Actions workflow building every platform gem, publishing through RubyGems
  trusted publishing (OIDC).
- **Publishing must be idempotent.** OIDC removes the one-time code; it does not make seven pushes
  atomic. A job dying after four pushes and then re-run hits "version already published" and fails
  again. Query RubyGems for each platform gem at that version and push only what is missing, so a
  re-run finishes the job. Without this, PR 1 does not fix the failure it exists to fix.
- **Verification stage before any publish.** Serve the built gems from a temporary local index,
  resolve on glibc and on Alpine, install, and exercise one real build. This is what proves Alpine
  selects `-musl` and the plain gem carries no binary. Checking `spec.files` cannot see a file that
  appeared between one rake task and the next, which is exactly how 0.25.2 shipped a stray binary.
- Builds Linux and musl gems on Linux runners, where Docker is present. `Rakefile:76` uses xgo,
  which is Docker-based.
- One-time trusted-publisher setup on RubyGems.

## PR 2: musl gems, the -gnu rename, and the plain gem

### Platform set

| Ruby gem platform | Go target | built by |
|---|---|---|
| `x86_64-darwin` | `darwin/amd64` | native, CGO_ENABLED=1 |
| `arm64-darwin` | `darwin/arm64` | native, CGO_ENABLED=1 |
| `x86_64-linux-gnu` | `linux/amd64` | xgo |
| `aarch64-linux-gnu` | `linux/arm64` | xgo |
| `x86_64-linux-musl` | musl amd64 | Docker `golang:1.25-alpine` |
| `aarch64-linux-musl` | musl arm64 | **see below** |

**xgo cannot build musl.** Its README lists darwin, linux, windows and freebsd with no libc
variants, so Docker is the primary route, not a fallback. xgo is confirmed good for `windows/amd64`
via mingw-w64, which PR 3 needs.

**arm64 musl needs a named mechanism.** `docker run golang:1.25-alpine` builds the runner's
architecture, which gives x86_64 and nothing else. Pick one and write it down: a GitHub arm64 Linux
runner, or QEMU via `docker buildx --platform linux/arm64`. QEMU is slower but needs no runner
availability. Do not leave this to implementation — an arm64 musl gem that never gets built is
worse than one never promised, and Apple-silicon Docker is most of the Alpine audience.

Set `spec.required_rubygems_version = '>= 3.3.22'` on the Linux variants so older RubyGems refuses
them rather than mis-installing. Bundler >= 2.5.6 resolves the new names. Existing users on
`x86_64-linux` may need `bundle lock --add-platform x86_64-linux-gnu`; say so in the release notes.
Update the Go-binary-to-gem comment at the top of `Rakefile`.

### The plain gem must stop shipping a binary

`rake build` runs the platform builds as prerequisites and Bundler's plain-gem action last, so
`lib/proscenium/ext/proscenium` still holds the last platform's binary when the plain gem is packed.
Published 0.25.2 contains an x86-64 Linux ELF. **Still true on master** — `proscenium.gemspec` and
`Rakefile` are byte-identical. The `-gnu` rename makes it worse: more hosts stop matching a platform
gem and land on the plain one.

- Gate `lib/proscenium/ext/**` in `proscenium.gemspec:22` on an environment variable the platform
  build tasks set. Comment why; the coupling is otherwise invisible.
- `lib/proscenium/builder.rb:29` raises a named error listing supported platforms when the library
  is absent, instead of letting `ffi_lib` produce an FFI `LoadError`.

Adding `clobber:ext` to `push:gem` cannot fix this: `push:gem` uploads an existing archive, and rake
runs a task once per invocation.

### CI and tests

- One `ruby-test` cell on `ruby:3.3-alpine`. The container needs Go installed and `bundle install`
  run; `GOTOOLCHAIN` cannot bootstrap without an existing Go binary, and `ruby:3.3-alpine` ships
  none. `apk add build-base` plus a Go install, then `go build -buildmode=c-shared`, then `bin/test`.
- A Minitest loading the gemspec, asserting `spec.files` excludes `lib/proscenium/ext/**` without
  the environment variable and includes it with it set.
- A test that a missing library raises the named error, pinning the message text.
- PR 1's verification stage is what proves the real archives resolve and install correctly.

---

## PR 3: Windows x64

### Phase 1: CI probe

No path fixes yet. Open a draft PR with CI plus the three changes without which the probe teaches
nothing:

- `.github/workflows/main.yml`: `windows-latest` in the `go-test` matrix and one `ruby-test` cell
  (single Rails version, as macOS is already trimmed). Leave `bun-test` alone. Use the `.dll` build
  step from `9da6f14f` and `shell: bash` on the Ruby steps.
- **`lib/proscenium/builder.rb:29`**: `ffi_lib(Gem.win_platform? ? "#{base}.dll" : base)`. Unchanged
  on master. Whether `LoadLibrary` appends `.dll` to a full path is unknown; if not, every Ruby test
  dies at library load and the probe reports nothing about paths. Zero risk on Unix.
- **`test/runtime/server_test.rb`**: skip on Windows with a message naming the reason. Windows Ruby
  does have `UNIXServer`; the hardcoded `/tmp` at `server.rb:122` is the problem, and it is
  load-bearing for socket-path length.
- Checkout: `core.symlinks true`, `core.longpaths true`, and
  `fixtures/dummy/node_modules/** symlink=dir` in `.gitattributes`.

Let it run red. That list sizes everything below, including whether `lib/` needs a Ruby counterpart
to Phase 2b — neither Ruby-side survey completed during planning, so Phase 2b covers Go only. That
is unexplored, not evidence that Windows is a Go-only problem.

### Phase 2a: finish F-GOUTILS-1 step 2 (behaviour-preserving)

Master already did most of this. `internal/plugin/css.go:40` calls `utils.UrlPathFromFsPath`;
`internal/resolver/resolve.go:95,161` call `gem.UrlPath()`; `F-GORESOLVE-1` landed in `8452092a`;
and `a4d5fa58` added a `path.Clean` to the containment check. Master's own doc comment on
`UrlPathFromFsPath` names what is left: "internal/plugin still carries three copies (dirname.go, and
`rootPathToUrlPath` in bundless.go, which has no boundary); they move here in the F-GOUTILS-1 step-2
pass." TODOS.md points at `dirname.go:32`, `bundler.go:356` and `bundless.go:406`.

Move those three onto `UrlPathFromFsPath` and delete `rootPathToUrlPath`, in a commit that does not
change behaviour beyond the one documented difference below, so Phase 2b applies the convention to
one copy rather than three.

**CRITICAL REGRESSION TEST.** `rootPathToUrlPath` (`bundless.go:427`) is a bare `CutPrefix` with no
boundary. `UrlPathFromFsPath` matches the app root at a `/` boundary only, so `/app-other/x.css` is
no longer treated as inside `/app`. That is a correctness improvement and a behaviour change: paths
that currently fall through the boundary-less trim will now report not-found, and the two plugin
callers need explicit "leave the path alone" handling rather than inheriting a silent trim. Test
both sides — a path under the root, and a sibling directory sharing the root's name prefix — through
each migrated call site, red against a naive migration.

### Phase 2b: one path convention, applied per site

**Every path held in a Go variable is slash-form.** This is already what most of the code does, and
it is already correct on Windows: Go's `os` package and the Win32 API both accept `/`. Ruby
cooperates — `Rails.root.to_s` and `Gem::Specification#full_gem_path` produce `C:/...`. Confirm on
the runner rather than assuming.

```
                    TWO PATH SPACES, ONE STRING TYPE

  URL space                                Filesystem space
  always "/"                               OS-form: "/" or "\", maybe "C:"
  what the browser asks for                what esbuild and os.* hand back

  /app/views/x.css                         /Users/j/app/app/views/x.css
  /node_modules/@rubygems/foo/a.js         C:\Users\j\app\app\views\x.css
          ^                                            |
          |  utils.UrlPathFromFsPath                   |  ToSlash at ingress
          |  GemRef.UrlPath()                          v
          +-------------------------------------  C:/Users/j/app/...

  THE ONLY DOORS esbuild comes through:
    1. top of each OnResolve / OnLoad callback:
       args.Path, args.ResolveDir, args.Importer
    2. resolveThroughEsbuild(), wrapping build.Resolve
    3. result.OutputFiles[].Path, in build_to_string

  FROZEN INPUTS — normalising these changes user-visible output:
    css.go:61  ast.CssLocalHash(args.Path)          -> CSS module class names
    css.go:67  filepath.Rel(AbsWorkingDir, ...)     -> mirrored by Ruby
    compile.go .manifest.json from esbuild metafile -> compared by Ruby as text

  ABSOLUTENESS IS SPACE-DEPENDENT. TWO PREDICATES, NEVER ONE:
    URL-root      leading "/"          bundler.go:263 "prepend the root"
                                       resolve.go:109 "replace leading / with ./"
    fs-absolute   "/" OR "C:/"         utils.go:47 bare-module check
                                       compile.go:170 already does this right
```

This diagram goes in the plan **and** as a doc comment above the predicates in
`internal/utils/utils.go`. That the rule lived nowhere is why February happened.

1. **Ingress normalisation, two doors not one.** Normalise `args` at the top of each callback. But
   esbuild is re-entered mid-callback at `internal/plugin/bundler.go:27`,
   `internal/plugin/bundless.go:49` and `internal/plugin/bundless.go:101`, each returning an `r`
   whose `.Path` esbuild produced. A top-of-callback rule does not cover those. Route all three
   through one wrapper that normalises the result — the three sites are already near-identical
   closures, so the wrapper removes duplication as well as closing the hole.
2. **Two predicates, classified per site.** `path.IsAbs("C:/x")` is false, but replacing every
   `path.IsAbs` with a drive-letter-aware one is the February mistake in the other direction. At
   `bundler.go:263` the comment reads "Absolute path - prepend the root to prepare for resolution" —
   make that true for `C:/app/x.js` and you get the root prepended to a path that has one. At
   `resolve.go:109` a drive path becomes `.C:/...`. Classify each of the nine sites
   (`bundler.go:263,276,338`, `bundless.go:352,441,478`, `resolve.go:109`, `utils.go:47`) by which
   question it is asking, and use the matching predicate. `compile.go:170`'s
   `filepath.IsAbs(cfg.OutputDir)` is master's own example of the right call.
3. **Keep `filepath` for genuine filesystem construction, behind named helpers.** Slash-form does
   not make the `path` package safe for filesystems: `path.Join` collapses `//server/share` into
   `/server/share`, destroying a UNC root, and it does not understand drive-root boundaries when
   cleaning `..`. Convert the incidental uses; keep `filepath.EvalSymlinks` (`bundler.go`,
   `bundless.go`) and `filepath.Rel` (`css.go:67`), and put any remaining filesystem-bound
   construction in a small named helper with `ToSlash` on the result.
4. **Frozen hash and manifest inputs.** `css.go:61` hashes `args.Path`, and `css.go:67` feeds
   `filepath.Rel` into a suffix that `Proscenium::Utils.css_module_suffix` mirrors in Ruby — the
   comment at `css.go:64-66` says "Change them together; test/css_module/suffix_test.rb checks that
   they agree." Codex adds that the esbuild fork's linker hashes `Source.PrettyPaths.Abs` while
   `MakePrettyPaths` normalises only the relative spelling, so those inputs can diverge. Changing
   the form of these paths changes CSS module class names, silently, and only on Windows. Extend
   `test/css_module/suffix_test.rb` to cover a path whose form the normalisation changes, and add a
   production manifest round-trip test. **This may surface that the esbuild fork needs a change,
   which would be a dependency this plan does not own and a legitimate NO-GO trigger.**
5. **Case-insensitive root comparison.** Windows may need it, since drive letters and directory
   names can differ in case between what Ruby sends and what esbuild returns. Decide from Phase 1
   evidence; do not add speculatively.
6. **A `forbidigo` rule in `.golangci.yml`**, narrowed to "not outside the named helpers" rather
   than a blanket ban, plus fencing direct `build.Resolve` outside the wrapper. A test asserting no
   backslash in URL paths is vacuous on Unix; the lint rule fences everywhere.

`internal/debug/debug.go` trims a prefix off a `runtime.Caller` filename, which is OS-form. Debug
output only. Fix with the same rule or leave it; do not let it become its own discussion.

**New helpers need tests.** Both predicates, covering leading `/`, `C:/`, `C:\`, UNC, relative and
empty. The resolve wrapper, covering an OS-form result becoming slash-form.

### Phase 3: test fixtures — repair or NO-GO

`fixtures/dummy/node_modules` carries **24 tracked symlinks** — `@rubygems/gem_npm`,
`@rubygems/gem_npm_ext`, `pkg`, `pnpm-file` and the `.pnpm/*/node_modules/*` links. Six Ruby and
seven Go test files resolve through them. Git for Windows defaults to `core.symlinks=false`, which
checks these out as text files holding their target path, and `filepath.EvalSymlinks` then behaves
differently. February never touched fixtures or checkout config.

The longest tracked path is 185 characters; with `D:\a\proscenium\proscenium\` that is about 212,
hence `core.longpaths`.

The Phase 1 probe already sets `core.symlinks=true` and the `symlink=dir` attribute. Necessary,
possibly not sufficient: Git for Windows picks file-symlink or directory-symlink per link, and a
file symlink pointing at a directory cannot be traversed. All 24 targets are directories.

**There is no fallback.** Either fixture materialisation is repaired, or the probe returns NO-GO.
Skipping the npm and `@rubygems` resolution tests would make CI green by deleting the checks that
cover most of what the resolver does, and declaring Windows supported on that run would be
declaring something untested. Regenerating the fixtures hoisted is worse: it stops exercising the
symlinked topology pnpm actually produces, on every platform, degrading macOS and Linux coverage to
make Windows look fine. A NO-GO here is a clean outcome — one CI run spent, nothing published,
issue #73 closed for musl and honest about Windows.

### Phase 4: packaging

- `Rakefile`: add `'x64-mingw-ucrt' => 'windows/amd64'` and the `Gem.win_platform?` extension in
  `compile:local`.

  **Not through xgo.** Measured 2026-09-20: `xgo -buildmode=c-shared -targets=windows/amd64` fails
  with `x86_64-w64-mingw32-ld: export_file.def:1: syntax error`, mingw-w64's linker rejecting the
  export definition Go generates for c-shared. Build Windows natively on a `windows-latest`
  runner, the way darwin already builds natively on macOS; the release workflow has that pattern
  and `9da6f14f`'s CI did the same. Only the cross-compiled Linux gems go through xgo.
- Confirm the mingw DLL loads under Ruby's UCRT build. FFI crosses the C ABI only and shares no CRT
  state, but this is a check on the runner, not an assumption. PR 1's verification stage covers it
  if that workflow gains a Windows leg.
- The `ffi_lib` change landed in Phase 1.

### Phase 5: docs

README supported-platforms table for all seven gem platforms, a line saying the `bun test` harness
is Unix-only, and an Alpine note in `docs/guides/`.

---

## What already exists

| Thing | Where | Reused or rebuilt |
|---|---|---|
| The four Go path fixes for Windows | `9da6f14f`, `4c6c6fe0`, `301ea4dd` | Reused as reference. Phase 2b takes the ideas, not the sprinkling. |
| xgo cross-compile loop | `Rakefile:70-90` | Reused for Windows; extended. musl bypasses it. |
| The canonical fs-path-to-URL rule | `utils.UrlPathFromFsPath`, with boundary and `path.Clean` | Reused. Phase 2a moves the last three copies onto it — it is F-GOUTILS-1 step 2, already specified in TODOS.md. |
| Gem matcher | `utils.GemFromFsPath`, tested in `test/utils_test.go` | Reused. |
| Correct fs-absolute check | `compile.go:170` `filepath.IsAbs(cfg.OutputDir)` | Reused as the worked example for Phase 2b item 2. |
| Go/Ruby CSS-suffix agreement test | `test/css_module/suffix_test.rb` | Extended rather than replaced. |
| Plain-gem packaging bug | Diagnosed previously, verified against published 0.25.2 | Fixed in PR 2. |

## NOT in scope

- **The `bun test` harness on Windows.** Its daemon binds a `UNIXServer` on a `/tmp` socket, and the
  `/tmp` hardcode is load-bearing for socket-path length.
- **Windows arm64 (`aarch64-mingw-ucrt`).** Not before x64 is proven.
- **FreeBSD.** No CI runner, rare for Rails.
- **Named Go types for the two path spaces.** Recorded in TODOS.md instead, with the three incidents
  as evidence. Should wait until F-GOUTILS-1 step 2 reduces the conversion sites.
- **A Ruby-side counterpart to Phase 2b.** Unexplored; Phase 1 sizes it.
- **`internal/css` path handling.** Not surveyed. February touched `css/mixins.go` for map keys, so
  Phase 1 may surface it.

## Failure modes

| Codepath | Realistic production failure | Test? | Handled? | Silent? |
|---|---|---|---|---|
| Plain gem on unsupported platform | FFI `LoadError` naming a path, no hint the platform is unsupported | Yes, PR 1 + PR 2 | Yes, named error | No |
| Alpine resolving `-gnu` not `-musl` | Installs, dlopen fails at first build | Yes, PR 1 verification | No | No |
| Partial release publish | Some platforms get the version; others resolve older | Idempotent push | Yes | No |
| Boundary added in Phase 2a | A sibling-prefix path stops resolving | Yes, regression test | Needs explicit caller handling | **Yes without the test** |
| CSS module hash input changes form | Stylesheet and view emit different class names; page renders unstyled | Yes, extended suffix test | No | **Yes without the test** |
| esbuild re-entry returning OS-form | Backslash flows past the ingress conversion into a URL | Windows CI | No | Yes on Windows |
| Fixture symlinks not materialised | Every `@rubygems` test fails | Phase 1 probe | NO-GO | No, loud |

No critical gaps remain. The three that would have been silent are covered by PR 1's idempotent
push, the Phase 2a regression test and the Phase 2b suffix test.

## Parallelization

| Step | Modules touched | Depends on |
|---|---|---|
| PR 1 release + verification | `.github/workflows/` | — |
| PR 2 musl, rename, plain gem | `Rakefile`, `proscenium.gemspec`, `lib/proscenium/`, `test/`, `.github/workflows/` | PR 1 (verification stage) |
| PR 3 Phase 1 probe | `.github/workflows/`, `lib/proscenium/`, `test/`, `.gitattributes` | — |
| PR 3 Phase 2a | `internal/plugin/`, `internal/utils/`, `test/` | Phase 1 GO |
| PR 3 Phase 2b | same, plus `internal/resolver/`, `internal/builder/`, `.golangci.yml` | Phase 2a |

- **Lane A:** PR 1 → PR 2 (sequential; PR 2's verification lives in PR 1's workflow).
- **Lane B:** PR 3 Phase 1 (independent).
- **Then:** Phase 2a → 2b → 3 → 4 → 5, sequential in `internal/`.

Launch A and B in parallel. **Conflict flag:** PR 2 and PR 3 Phase 1 both edit
`.github/workflows/main.yml` and `lib/proscenium/builder.rb`. Land PR 2 first or expect a small
manual merge on both.

## Implementation Tasks

- [ ] **T1 (P1, human: ~1.5 days / CC: ~1.5 hrs)** — release — Tag-triggered release workflow, trusted publishing, idempotent push, artifact verification stage
  - Surfaced by: Architecture issue 2 and cross-model tensions 3 and 4 — seven OTP prompts, a recorded partial publish, and OIDC not making retries idempotent
  - Files: `.github/workflows/release.yml`, `Rakefile`
  - Verify: dry-run publishing all gems; kill the job mid-run and re-run it to completion
- [ ] **T2 (P1, human: ~2 hrs / CC: ~20 min)** — packaging — Gate `lib/proscenium/ext/**` out of the plain gem; raise a named error when absent
  - Surfaced by: Architecture issue 1 — published 0.25.2 contains an x86-64 Linux ELF; still true on master
  - Files: `proscenium.gemspec`, `Rakefile`, `lib/proscenium/builder.rb`
  - Verify: gemspec Minitest with and without the env var; error-path test; PR 1's verification stage
- [ ] **T3 (P1, human: ~1 day / CC: ~45 min)** — packaging — Rename Linux gems to `-gnu`, add both `-musl` gems with a named arm64 route, set `required_rubygems_version`
  - Surfaced by: Step 0 search check and tension 4 — a bare Linux platform matches musl; `golang:1.25-alpine` builds host arch only
  - Files: `Rakefile`, `proscenium.gemspec`, `.github/workflows/main.yml`
  - Verify: PR 1's verification stage resolves on glibc and Alpine, both architectures
- [ ] **T4 (P2, human: ~2 hrs / CC: ~20 min)** — ci — Windows probe: matrix cells, `.dll` `ffi_lib`, runtime-test skip, checkout config
  - Surfaced by: Context — February reverted after pre-fixing blind
  - Files: `.github/workflows/main.yml`, `lib/proscenium/builder.rb`, `test/runtime/server_test.rb`, `.gitattributes`
  - Verify: draft PR runs; read the red; GO/NO-GO
- [ ] **T5 (P1, human: ~half day / CC: ~40 min)** — internal — F-GOUTILS-1 step 2: move `dirname.go:32`, `bundler.go:356`, `bundless.go:406` onto `UrlPathFromFsPath`; delete `rootPathToUrlPath`
  - Surfaced by: Code quality issue 4, narrowed after checking master — `css.go` and `resolve.go` already migrated
  - Files: `internal/plugin/dirname.go`, `internal/plugin/bundler.go`, `internal/plugin/bundless.go`
  - Verify: `GOWORK=off go test ./test`
- [ ] **T6 (P1, human: ~2 hrs / CC: ~20 min)** — test — CRITICAL regression test: the root boundary `rootPathToUrlPath` lacks
  - Surfaced by: Test review — `rootPathToUrlPath` is a bare `CutPrefix`; `UrlPathFromFsPath` requires a `/` boundary, so `/app-other/x.css` changes answer
  - Files: `test/utils_test.go`, `test/build_to_string_test.go`
  - Verify: red against a naive migration, green after
- [ ] **T7 (P1, human: ~3 hrs / CC: ~25 min)** — internal — One normalising wrapper around `build.Resolve`; normalise `args` at callback top
  - Surfaced by: Code quality issue 5 — esbuild re-entered at `bundler.go:27`, `bundless.go:49`, `bundless.go:101`
  - Files: `internal/plugin/bundler.go`, `internal/plugin/bundless.go`, `.golangci.yml`
  - Verify: unit test that an OS-form result comes back slash-form
- [ ] **T8 (P1, human: ~2 days / CC: ~1.5 hrs)** — internal — Two predicates classified per site; `filepath` kept behind named helpers; narrowed `forbidigo` rule
  - Surfaced by: Cross-model tension 1 — a blanket swap produces `C:/app/C:/app/x.js` at `bundler.go:263` and `.C:/...` at `resolve.go:109`
  - Files: `internal/utils/utils.go`, `internal/plugin/*.go`, `internal/resolver/resolve.go`, `internal/builder/*.go`, `.golangci.yml`
  - Verify: `golangci-lint run`; `GOWORK=off go test ./test`; Windows CI cell
- [ ] **T9 (P1, human: ~1 day / CC: ~1 hr)** — test — Freeze hash and manifest inputs; extend `suffix_test.rb`; add a manifest round-trip test
  - Surfaced by: Cross-model tension 2 — `css.go:61,67` hash a path Phase 2b changes, and Ruby mirrors it
  - Files: `test/css_module/suffix_test.rb`, `test/compile_test.go`, `internal/plugin/css.go`
  - Verify: agreement test covers a path whose form normalisation changes; may trigger NO-GO
- [ ] **T10 (P2, human: ~1 hr / CC: ~15 min)** — docs — Path-space diagram in the plan and above the predicates in `utils.go`
  - Surfaced by: Architecture issue 3 — the convention existed only as prose
  - Files: `internal/utils/utils.go`
  - Verify: review reads it
- [ ] **T11 (P3, human: ~20 min / CC: ~5 min)** — docs — TODOS.md entry for typed path spaces, citing the three incidents
  - Surfaced by: TODOS step — February, `a4d5fa58`, and this review's own near-miss
  - Files: `TODOS.md`
  - Verify: entry names the prerequisite (F-GOUTILS-1 step 2)
- [ ] **T12 (P2, human: ~2 hrs / CC: ~20 min)** — docs — Supported-platforms table, Unix-only harness note, Alpine guide note
  - Surfaced by: Phase 5
  - Files: `README.md`, `docs/guides/`, `Rakefile`
  - Verify: table matches `PLATFORMS`

## Verification

```bash
# Go, all platforms
GOWORK=off go test ./test

# Ruby, all platforms
bundle exec rake compile:local && bin/test

# Lint both languages, per CLAUDE.md
bundle exec rubocop -P --fail-level C && golangci-lint run
```

The musl check needs Go installed in the container; `ruby:3.3-alpine` ships none, and `GOTOOLCHAIN`
cannot bootstrap without an existing Go binary. Write the real command as part of T3 rather than
carrying a broken one here.

What actually proves it: PR 1's verification stage resolving and installing the built gems on glibc
and Alpine for both architectures, then exercising a build. Install the plain gem where no platform
gem matches and read the error. For Windows, the same asset requests on a Windows runner, asserting
every URL in the response body uses forward slashes. A green `go test` proves neither the FFI
boundary nor the gem packaging, and those are the two things never proven in February.

## Open questions, to settle with evidence

- Does the `joelmoss/esbuild-internal` fork return OS-form or slash-form paths from its callbacks on
  Windows, and does it accept a slash-form `C:/...` as `result.Path`? Both directions matter.
- Does the fork's `Source.PrettyPaths.Abs` hashing diverge from `css.go:61` once paths are
  normalised? If it needs a fork change, that is a NO-GO trigger.
- Do `Rails.root.to_s` and `Gem::Specification#full_gem_path` arrive slash-form on Windows?
- Does `actions/checkout` materialise the 24 fixture symlinks as traversable directory symlinks?
- Does Windows need case-insensitive root comparison?
- How much Windows-specific work does `lib/` need?
- arm64 musl: GitHub arm64 runner or QEMU? Decide before writing T3.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Outside Review | `codex exec` (gpt-6-astra), plan-review phase | Independent 2nd opinion | 1 | completed | 7 findings, 5 folded via tensions 1-5, 2 absorbed into T1/T3 |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | clean | 6 issues + 5 cross-model tensions, 0 unresolved, 0 critical gaps |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | not applicable, no UI surface |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

**OUTSIDE COVERAGE:** provider codex (`gpt-6-astra`, reasoning effort high), phase plan-review,
completed. Recommendation was "revise before implementation because the path rules introduce
concrete failures and the release checks do not validate the artifacts users install." Findings 1,
2 and 3 were verified against the source before being brought to the user. All seven were acted on.

**CROSS-MODEL:** native and external reviews overlapped on the path-space diagnosis and diverged on
the remedy. The native review proposed one absoluteness predicate used at every site; the outside
review showed that produces `C:/app/C:/app/x.js` at `bundler.go:263` and `.C:/...` at
`resolve.go:109`, which the source confirms. Tension 3 reversed a native recommendation the user had
already accepted. The outside review independently found the CSS-module hash hazard
(`css.go:61,67`), which the native review missed entirely.

**VERDICT:** ENG CLEARED — ready to implement, from a new branch cut off `master`. PR 3 is gated on
the Phase 1 probe, and NO-GO is an accepted outcome.

NO UNRESOLVED DECISIONS
