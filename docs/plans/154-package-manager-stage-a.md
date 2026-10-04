# #154 Stage A results

Evidence for the Stage A pilot of [the package manager plan](154-package-manager.md#stage-a-execution-contract).
Each leg records its commands, tool versions, revisions and verdicts. Legs that run against the
maintainer's private checkouts (london, hue) record no source or manifest contents, only what is
needed to repeat the run.

## Summary

**Recommendation: GO for pnpm and for Bun**, pending the maintainer's sign-off on #154. Neither
adapter hit the kill criterion, and every Gate A row that Stage A could measure passed.

| | pnpm | Bun |
|---|---|---|
| Lines measured | 10.33.1, 10.34.4, 11.28.4, 12.9.1 | 1.4.0, 1.4.2 |
| A gem's dependencies through a context (C04, C46) | london and platform: every hue entry that today's install builds still builds the same, but one test file | codaset: every proscenium-ui entry whose imports its manifest declares |
| No app edge needed | yes | yes |
| One instance of a shared peer (C12, C13) | yes; pnpm 10 splits after an app bump with default settings, which `pnpm dedupe` repairs | yes |
| Repeated frozen installs byte-identical (C08) | yes | yes |
| Version-less context, `workspace:*`, no registry (C42) | yes | yes |
| Plain dependencies instead of peers (C43) | recorded; the app's overrides decide | recorded |
| Git dependency scripts unapproved (C55, part) | none run; `prepare` fails the install | none run, silently |
| Registration (C51) | spliced into an existing pnpm-workspace.yaml | needs an explicit linker and `trustedDependencies`; codaset's 139 tests pass |

Settled here: no descriptor receipt; no app edge to a context; registration splices into existing
files; Bun requires an explicit linker (else it switches codaset to the isolated store) and an
explicit `trustedDependencies` (else a gem can introduce a default-trusted package whose script
runs); a production install can skip an excluded gem's context with a negative filter; the
qualification hosts are macOS arm64 and Linux x86_64 and aarch64, since no app runs on Windows;
and the frozen check compares whole regenerated contexts, so a hand edit that leaves the hash alone
is still caught.

For Stage B and C to take on:

- **pnpm 10's peer split.** The CLI's peer-sharing check catches it; whether `install` also runs
  `pnpm dedupe` on pnpm 10 is a design choice.
- **Errors that name the gem.** pnpm fails an install for a Git dependency needing `prepare`, and
  its message names only the package; Bun skips such scripts without a word.
- **Serving nested copies.** Under Bun's hoisted linker a conflicting copy is a real directory
  under `.proscenium/packages/<gem>/node_modules/`, which the serving allow-list must cover.
- **proscenium-ui's manifest** imports `react`, `clsx` and `trix` without declaring them, and must
  before it opts in.

Not done in Stage A: the hermetic registry and committed tarballs (the CI tests reach npm and
GitHub), proscenium-ui at a pinned revision in CI, the app legs on Bun 1.4.0 (only the peer probe
and Git script check ran there), and codaset's pages in a browser. The london leg, the CI tests and
the peer probe were repeated on Node 22.22.2 with the same results as on Node 26.

## london on pnpm (4 October 2026)

**Question.** Can a hand-written context give hue its JavaScript dependencies through pnpm, with
the Stage A resolver seam routing hue's bare imports, so that every hue entry london precompiles
builds exactly as it does today?

**Verdict: GO for this leg, with the gaps listed below.** With the seam on, 77 of london's 78 hue
entries build the same module graph as today, bundled and unbundled, whether or not the app
references the context. The 78th is a test file london's precompile list picks up, which imports
a gem devDependency; the seam reports it as a named error where today's engine silently leaves a
broken browser import.

### Setup

| | |
|---|---|
| Command | `ruby test/package_manager/stage_a/leg.rb LONDON HUE CONFIG OUT` (CONFIG names hue and pnpm) |
| Host | macOS 27.0.1 (26A434), arm64 |
| Node | 26.10.0 |
| pnpm | 10.33.1, selected by london's `packageManager` field |
| Go | 1.27.1, `GOWORK=off` |
| Ruby | 3.4.11 (london's), to read its bundle |
| Proscenium | branch `stage-a/154-scaffold`, the seam from 6db5a4e7 |
| london | 8dc567de |
| hue | checkout at 7400c7a9 |

hue has three pins in london, all different: `BUNDLE_LOCAL__HUE` points Bundler at the checkout
(7400c7a9), Gemfile.lock records 7904fb90, and package.json's `github:` pin is 22e66043. That is
the double-pin drift the plan exists to remove. The proof reads hue's files and manifest from the
checkout, which is what london's bundle loads.

The script copies london's package.json, pnpm-lock.yaml and .npmrc, and the app files its
aliases point at, into three directories, and never writes to london or hue. london's Proscenium
settings (entry points, aliases, externals) come from a local CONFIG file, not the repository.

- **base**: london as it is, `pnpm install --frozen-lockfile`.
- **unref**: the `github:` pin removed, `.proscenium/packages/*` registered in a new
  pnpm-workspace.yaml, and `.proscenium/packages/hue/package.json` projected from hue's manifest
  (dependency-context-v1 fields; the `projectionSha256` is provisional until Stage B defines the
  encoding). `pnpm install`.
- **ref**: as unref, plus `"@rubygems/hue": "workspace:*"` in the app's dependencies.

It then builds every hue entry london precompiles (78)
through `test/package_manager/stage_a/probe`, with london's aliases and externals, bundled and
unbundled, with the seam on and off. Each build is compared with base: bundled by the modules
esbuild includes, unbundled by the import URLs, both reduced to `package@version/path` so the
three directories compare.

### Results

| Cell | Bundled, matching base | Unbundled, matching base |
|---|---|---|
| unref, seam off | 71 of 78 | 78 of 78 (see below) |
| unref, seam on | 77 of 78 | 77 of 78 |
| ref, seam off | 78 of 78 | 78 of 78 |
| ref, seam on | 77 of 78 | 77 of 78 |

- **The seam works without an app edge.** unref and ref give the same results with the seam on,
  so the plan's default of no app dependency on a context holds on pnpm 10.33.1 for hue.
- **The one failure is the intended error.** The entry that fails with the seam on is a test file
  that london's precompile list picks up. It imports a
  testing library that is one of hue's devDependencies, which the projection leaves out. The seam
  fails the build with `gem "hue": could not resolve "<package>" from its dependency context`;
  base and the seam-off cells left the import external, so the browser would have failed instead.
  London should not precompile test files.
- **Without the seam, an unreferenced context is invisible to the engine.** Seven bundled entries
  silently lose modules: hue's dependencies are under the context only, and today's engine falls
  back to the app root, misses them and makes them externals. This is the positive control.
- **An app edge alone already works with today's engine.** With `workspace:*`, pnpm links
  `node_modules/@rubygems/hue` to the context, and the existing branch in
  `internal/plugin/bundler.go` that prefers `node_modules/@rubygems/<gem>` resolves from it: ref
  with the seam off matches base on every entry.
- **The unbundled seam-off control proves nothing here.** hue's checkout has its own
  `node_modules` (it is a working checkout), and today's unbundled chain falls back to the gem
  root, so it finds hue's own dependencies there. The CI half below, with `stage_a_hue_shape`
  installed read-only and without a `node_modules`, is the real control.
- **Frozen installs are stable (C08).** In unref and ref, two repeated
  `pnpm install --frozen-lockfile` runs and a frozen install after deleting every `node_modules`
  exit 0 and leave package.json, pnpm-lock.yaml, pnpm-workspace.yaml and the context
  byte-identical.
- **The lock.** The bridge adds one importer, `.proscenium/packages/hue`, and drops the
  `github:` pin's package; no `@rubygems/*` entry resolves to a registry. pnpm reports the same
  ignored build scripts as base (two of the app's own dependencies).

### React

london does not get React from npm: its Proscenium configuration makes React an external, and
the page supplies it. So:

- **Bundled**, every cell keeps React external: zero React modules in any output, and across the
  77 entries that build, the same 56 bare `react` imports as base, all left for the page to
  supply. One React instance, but because of london's configuration, not pnpm. This does not test C12 and is not counted as passing it.
- **Unbundled** builds ignore `external`, so hue's `react` imports resolve to npm React 18.3.1,
  in base and with the seam alike: hue's checkout copy in base, the pnpm store copy with the seam,
  both 18.3.1, one copy across all hue entries. A page mixing these with the React london
  supplies would load two. This is today's behaviour, unchanged by the bridge, and london builds
  bundled.
- **C43, native result on pnpm 10.33.1.** hue declares `react` and `react-dom` as plain
  dependencies. pnpm installs react 18.3.1 and react-dom 18.3.1 into the context
  (`autoInstallPeers: true`, london's lock setting), as links into the store. The app declares no
  React, so there is nothing to share and nothing to split.

### CI half: `stage_a_hue_shape`

`test/package_manager/stage_a/hue_shape_test.rb`, run by the `stage-a` CI job (ubuntu-latest,
pnpm 10.33.1) and locally with `STAGE_A=1 bin/test test/package_manager/stage_a/` (macOS 27.0.1,
Node 26.10.0, pnpm 10.34.4). `stage_a_hue_shape` has hue's manifest shape and is installed by
Bundler as a Git source into a read-only bundle, so its root has no `node_modules`. The test
writes its context into an app that declares nothing, registers it, runs `pnpm install`, and
builds the gem's entry through `Proscenium::Builder` with and without the seam.

| Check | Result |
|---|---|
| The gem root has no `node_modules` and is not writable | yes |
| The lock has the context as a workspace, no `@rubygems` package, and the context has no `version` (C42) | yes |
| react, react-dom and the `github:` dependency, all declared as plain dependencies, are linked into the context from the store (C43) | yes |
| Two frozen installs leave package.json, the lock, the workspace file and the context byte-identical (C08) | yes |
| Bundled with the seam: one React, one react-dom, the `github:` dependency, all from the store | yes |
| Unbundled with the seam: imports are real store paths, none under the gem's URL | yes |
| Without the seam: no dependency resolves, bundled or unbundled (the positive control) | yes |

With the seam disabled in Go (`StageAContext` never matching), the two seam checks fail, so the
test can fail. It needs the network (npm and GitHub) until the hermetic registry exists, which is
why it runs only with `STAGE_A=1`.

### Not covered by this leg yet

- Node 22, the pnpm line platform uses and the CI floor; london ran 10.33.1 on Node 26 and the
  CI half runs 10.33.1 (CI) and 10.34.4 (locally).
- The peer probe (C12): a non-latest in-range pin, and the `auto-install-peers=false` and
  `resolve-peers-from-workspace-root=false` variants. london's externals take React out of the
  question, so C12 needs platform or a fixture.
- The drift cases that decide whether a descriptor receipt is needed.
- Whether london, platform or codaset nest a Rails app in an enclosing JS workspace, and the hosts
  each develops and deploys on.

## platform on pnpm (4 October 2026)

The london leg repeated for platform, which also uses hue (77 entries: platform precompiles one
fewer hue file), with `leg.rb` and a local CONFIG for platform's settings.

| | |
|---|---|
| pnpm | 10.34.4, selected by platform's `packageManager` field |
| platform | e9754d69b |
| hue | the same checkout as london (7400c7a9), through `BUNDLE_LOCAL__HUE` |

| Cell | Bundled, matching base | Unbundled, matching base |
|---|---|---|
| unref, seam off | 68 of 77 | 77 of 77 |
| unref, seam on | 76 of 77 | 73 of 77 |
| ref, seam off | 77 of 77 | 77 of 77 |
| ref, seam on | 76 of 77 | 73 of 77 |

- **Same shape as london.** With the seam, every bundled entry but the test file matches, with or
  without an app edge; without the seam an unreferenced context loses modules, and an app edge
  alone works with today's engine.
- **platform already has a pnpm-workspace.yaml**, holding a `minimumReleaseAge` policy and
  comments. Registration has to splice the context pattern into it as text, as the plan says;
  `context.rb` does, and the install ran under that age gate.
- **An app override decides React, for the context too (C16).** hue declares
  `react: ^18.3.1` as a plain dependency, but platform's package.json overrides React for every
  package, and pnpm links the context to the app's override version. The three unbundled
  differences are exactly that: base resolved React from hue's checkout `node_modules`, the seam
  from the app's overridden copy, so unbundled hue now shares the app's React where base did not.
  Bundled, React is an external in platform as in london.

## codaset on Bun (4 October 2026)

**Question.** Can proscenium-ui get its dependencies from a context on Bun, what does registering
a context do to codaset's install, and do codaset's pages and `bun test` harness survive it (C51)?

**Verdict: GO for this leg, with one author fix needed in proscenium-ui and the gaps below.**
Registration needs the explicit linker the plan requires: without one, Bun 1.4.2 switches codaset
from its hoisted `node_modules` to the isolated store. With `linker = "hoisted"` and an empty
`trustedDependencies`, codaset's layout is unchanged and its 139 `bun test` tests pass. With the
seam on, every proscenium-ui entry whose imports its manifest declares builds as it does today;
the eleven that do not are files importing packages proscenium-ui never declared.

### Setup

| | |
|---|---|
| Command | `ruby test/package_manager/stage_a/leg.rb CODASET PROSCENIUM_UI CONFIG OUT` (CONFIG names proscenium-ui and Bun) |
| Host | macOS 27.0.1 (26A434), arm64 |
| Bun | 1.4.2 |
| Node | 26.10.0 |
| Ruby | 4.0.3 (codaset's), to read its bundle and run its harness |
| codaset | eb36cb5 |
| proscenium-ui | checkout at fc6640a, which Gemfile.lock also records; codaset's package.json takes it from the hosted registry at `^0.2.1` |

Cells, as for london, with Bun's registration (`workspaces` in package.json): **base** (frozen,
as today), **reg** (registered, no linker setting, to see what Bun picks), **unref-hoisted** and
**unref-isolated** (linker set, empty `trustedDependencies`, no app edge) and **ref-hoisted**
(plus `"@rubygems/proscenium-ui": "workspace:*"`). The entries are proscenium-ui's own JS and CSS
(40).

### Install layout

| Cell | Store | Root `node_modules` entries | Context `node_modules` |
|---|---|---|---|
| base | none (hoisted) | 18 | n/a |
| reg, no linker | `.bun` (isolated) | 6 | links into the store |
| unref-hoisted, ref-hoisted | none (hoisted) | 18 | none: dependencies hoisted to the root |
| unref-isolated | `.bun` | 6 | links into the store |

- **Registration switches the linker unless one is set (settles the plan's requirement on
  1.4.2).** In a codaset worktree with its existing hoisted tree, registering with no linker
  setting moved the old tree to `node_modules/.old_modules-<hash>` and installed the isolated
  store. With `linker = "hoisted"` the layout stayed exactly as before: 18 root entries, no store,
  nothing moved aside.
- **Hoisted puts context-only dependencies at the root**, and Bun links
  `node_modules/@rubygems/proscenium-ui` to the context even with no app edge. Both mean today's
  engine already finds proscenium-ui's dependencies under hoisted (40 of 40 match base with the
  seam off), and that the app can import a package only a gem declares (C47).
- **Hoisted nests conflicting copies under the context.** A synthetic app on `ms` 2.1.3 with two
  contexts, one on `ms` 2.0.0: Bun put 2.0.0 as a real directory at
  `.proscenium/packages/<gem>/node_modules/ms`, kept 2.1.3 at the root for the other, and hoisted
  a context-only package to the root, where the app could resolve it. Under isolated all three are
  links into the store and the app cannot resolve the context-only package. So under hoisted the
  serving allow-list must cover `.proscenium/packages/<gem>/node_modules/`, as the plan's Identity
  and URLs section anticipated.

### Results

| Cell | Bundled, matching base | Unbundled, matching base |
|---|---|---|
| unref-hoisted, seam off | 40 of 40 | 40 of 40 |
| unref-hoisted, seam on | 29 of 40 | 28 of 40 |
| unref-isolated, seam off | 37 of 40 | 39 of 40 |
| unref-isolated, seam on | 29 of 40 | 28 of 40 |
| ref-hoisted, seam off | 40 of 40 | 40 of 40 |
| ref-hoisted, seam on | 29 of 40 | 28 of 40 |

- **The eleven seam failures are proscenium-ui's manifest, not the bridge.** Eleven form-field
  files import `react`, `clsx` or `trix`, none of which proscenium-ui's package.json declares. The
  seam fails each with `gem "proscenium-ui": could not resolve "<package>" from its dependency
  context`. Today nothing provides them either: base leaves the imports external and the browser
  would fail. codaset does not use those components. proscenium-ui should declare them, React as a
  peer, before it opts in.
- **The twelfth unbundled difference is the local checkout.** One entry's `@floating-ui/dom`
  resolves in base to the copy in proscenium-ui's own checkout `node_modules` (1.7.6) and with the
  seam to the context's (1.8.0). An installed gem has no such directory.
- **Isolated without the seam is the control.** Three bundled entries lose modules, because
  today's engine cannot see dependencies that live only under the context.
- **The seam's results do not depend on the linker or an app edge.**

### Scripts and `trustedDependencies`

Bun 1.4.2 trusts 367 packages by default (`bun pm default-trusted`). Measured with
`simple-git-hooks`, which is on that list and whose postinstall writes a Git hook:

| Where the package comes from | `trustedDependencies` absent | `trustedDependencies: []` |
|---|---|---|
| the app's own dependency | script ran | blocked, reported |
| a gem's context | script ran | blocked, reported |

So an explicit array replaces the default list, and without one a gem can introduce a package
whose install script runs unapproved. That settles the plan's requirement for an explicit
`trustedDependencies` on Bun. (`esbuild`, also on the list, is special-cased: with no array Bun
reports "ignoring esbuild lifecycle scripts"; with `[]` it is blocked like any other.)

### CI half: `bun_test.rb`

Run by the `stage-a` CI job (Bun 1.4.2) and locally with `STAGE_A=1`. From the fixture gems, under
both linkers: the nested and linked `ms` copies above, each widget bundling its own `ms` and the
app's single React, the unbundled URL of the nested copy, and the `trustedDependencies` result for
a gem-introduced `simple-git-hooks`. With the seam disabled in Go, the isolated bundle and the
nested-copy URL checks fail. Under hoisted, today's engine already reaches the nested copy, through
the `node_modules/@rubygems/<gem>` link Bun creates for every workspace.

### codaset's harness (C51)

In a worktree of codaset: `bun test` with codaset's Ruby passed 139 of 139 tests in 12 files
before registration, after registering with no linker (the isolated switch), and after
registering with `linker = "hoisted"` and `trustedDependencies: []`. In the last state, a frozen
install after deleting `node_modules`, and a second frozen install, exit 0 and leave package.json,
bun.lock, bunfig.toml and the context byte-identical. The harness runs codaset's own Proscenium
(0.25.3), so this shows registration does not disturb it; it does not exercise the seam.

### Not covered by this leg yet

- Bun 1.4.0, the plan's floor; only 1.4.2 ran, on Node 26.
- codaset's unbundled pages in a browser (C51's other half).
- The peer probe (C12) on Bun.

## Peers (C12, 4 October 2026)

`ruby test/package_manager/stage_a/peers.rb OUT`, with `PNPM` and `BUN` naming the manager
command. A synthetic app pins `react` 18.2.0, the latest 18.x being 18.3.1; one context declares
`react: ^18.0.0` as a peer. Each cell installs, bumps the app to 18.3.1 and installs again, and on
pnpm then runs `pnpm dedupe`; each time it checks, with Node's `require.resolve` from the app root
and from the context, whether both reach one real React file. Every cell was run with the
context referenced from the app and not, with the same result.

| Manager | Setting | At the 18.2.0 pin | After the bump | After `pnpm dedupe` |
|---|---|---|---|---|
| pnpm 10.33.1, 10.34.4 | default (`auto-install-peers=true`) | shared | **split**: context stays on 18.2.0 | shared |
| pnpm 10.33.1, 10.34.4 | `auto-install-peers=false` | shared | shared | shared |
| pnpm 10.33.1, 10.34.4 | `resolve-peers-from-workspace-root=false` | shared | **split** | shared |
| pnpm 11.28.4, 12.9.1 | all three | shared | shared | shared |
| Bun 1.4.0, 1.4.2 | hoisted, isolated | shared | shared | n/a |

- **C12 is not NO-GO.** The non-latest pin is shared everywhere. The only split is pnpm 10 after
  the app bumps its React, with default settings, which is the review probe's finding repeated on
  both lines the apps use. A native setting prevents it (`auto-install-peers=false`), a native
  command repairs it (`pnpm dedupe`), and pnpm 11 and 12 do not split at all.
- **What the CLI does about the split is a Stage B decision:** the plan's peer-sharing check
  (exit 5 naming the package) catches it; whether `install` should also run `pnpm dedupe` on
  pnpm 10, or tell the user to, is open.
- **The real apps barely exercise this.** london and platform serve React outside npm in bundled
  builds, platform's overrides pin it for every package, and codaset has no React.


## Git dependency scripts (C55, 4 October 2026)

A context depending on a Git package whose `prepare`, `install` and `postinstall` scripts write
marker files, served from a local bare repository over `git+file://`.

| Manager | With `prepare` | `install` and `postinstall` only | Scripts run |
|---|---|---|---|
| pnpm 10.33.1, 10.34.4 | install fails: `ERR_PNPM_GIT_DEP_PREPARE_NOT_ALLOWED` | exit 0, "Ignored build scripts" | none |
| pnpm 11.28.4, 12.9.1 | install fails: `ERR_PNPM_GIT_DEP_PREPARE_NOT_ALLOWED` | install fails: `ERR_PNPM_IGNORED_BUILDS` | none |
| Bun 1.4.0, 1.4.2 (empty `trustedDependencies`) | exit 0, nothing reported | exit 0, nothing reported | none |

No line runs a gem-introduced Git dependency's scripts without approval, so C55's Stage A part
passes. Two consequences for Stage B: on pnpm a Git dependency that needs `prepare` stops the
install until the app allows it, and how to name a Git package in `onlyBuiltDependencies` changed
between pnpm 10.33.1 (the name, or `allowBuilds`) and 10.34.4 (`<name>@git+…#<sha>`), so the CLI's
error should name the gem that introduced it and the exact entry to add; and Bun skips
the scripts silently, so the CLI should list them itself. `git_scripts_test.rb` checks this in CI,
with the app's approval as the control that the scripts would otherwise run.

## Production installs (4 October 2026)

Can a production install leave out the context of a gem that is only in an excluded Ruby group?
A synthetic app with two contexts, one standing for a development-only gem:

| Command | Excluded gem's context installed | Running gem's context and the app installed |
|---|---|---|
| `pnpm install --prod --frozen-lockfile` (10.34.4) | yes | yes |
| ...with `--filter='!@rubygems/<gem>'` | no | yes |
| `bun install --production --frozen-lockfile` (1.4.2) | yes | yes |
| ...with `--filter='!@rubygems/<gem>'` | no | yes |

Both managers can, with a negative workspace filter, and the frozen lockfile still applies. So
`install --frozen --production` can pass one filter per excluded gem; without one, an excluded
gem's JS dependencies are installed in production too, which is harmless but wasted.

## The apps' layout and hosts (4 October 2026)

None of london, platform or codaset sits inside an enclosing JS workspace: no directory above any
of them has a package.json or pnpm-workspace.yaml. All three are developed on macOS arm64, run CI
on Ubuntu, and deploy as Linux containers built from `ruby:*-slim` images; their Gemfile.locks
declare Linux x86_64 and aarch64 among their platforms. None runs on Windows. So the qualification
hosts for v1 are macOS arm64 and Linux x86_64 and aarch64.

## Descriptor receipt (4 October 2026)

**Decision: no receipt.** `drift_test.rb` applies each drift case alone to a clean app and checks
that `Context.drift`, which reads only the registration, the committed contexts and the installed
gems, reports it:

| Drift | Detected without a receipt |
|---|---|
| The gem changes revision or source, but not its dependencies | nothing to detect: the context is still correct |
| The gem changes its dependencies | yes, the context's `projectionSha256` no longer matches |
| The projection version changes | yes, from the context's `projection` field |
| The registration is removed | yes, from pnpm-workspace.yaml or package.json |
| A participating gem has no context | yes |
| A context's gem no longer participates | yes, as an orphan |

A changed revision that leaves the dependencies alone needs no install, so a receipt would only
add a file to keep in step. The locked source identity the CLI needs is in Gemfile.lock.

## Browser identity (4 October 2026)

`PLAYWRIGHT=<node_modules/playwright> ruby test/package_manager/stage_a/identity.rb OUT`. An app
on pnpm 10.34.4 declares preact 10.26.9; a gem takes preact as a peer through its context. Each
page's modules are built unbundled through `Proscenium::Builder` with the seam on, following every
import as the middleware would serve it, and loaded in Playwright's Chromium (1.63.0).

| Page | How the app imports preact | preact URLs | `Component` from app and gem identical |
|---|---|---|---|
| page | `preact` | one, the store's real path | **yes** |
| control | by its link path, `/node_modules/preact/...` | two | no |

So two link paths to one file load as one module once the engine resolves real paths, and as two
when they are left as links, which is the control. This is the unbundled half of the identity
requirement; the bundled half is the Go seam specs and the CI tests.

The probe uses preact, not React, for a reason worth recording: npm's React is CommonJS, and an
unbundled page cannot load it at all ("Dynamic require of .../react.development.js is not
supported"), with or without the bridge. That is why london and platform serve an ESM React of
their own, and why one React instance there is a matter of their configuration rather than of
pnpm. An app that unbundles React from npm is not a case v1 has to serve.

## Re-estimate before Stage B (proposed, 4 October 2026)

The plan makes a re-estimate a gate before Stage B. Stage A's evidence shrinks the unknowns: no
receipt, no app edge, no NO-GO adapter, and the seam already covers every lookup site Stage C has
to make real. Proposed, for the maintainer to accept or change on #154:

| Stage | Work | Estimate (engineer / with Claude Code) |
|---|---|---|
| B: Ruby CLI | `exe/proscenium` and four commands, manager selection and capability table, registration splices (pnpm YAML, Bun package.json and bunfig), project lock and install marker, manager runner, peer-sharing and lock checks, error codes with golden outputs, installed-CLI release check | 2-3 weeks / 3-5 days |
| C: engine | the context map from `bundled_gems.rb` to Go in both config sites, the seam made real, real-path identity, serving nested copies under `.proscenium/packages/*/node_modules/`, adoption, staleness, install-in-progress refusal, mapping generations, the daemon | 2-3 weeks / 3-5 days |
| D: qualification | release-gate rows on macOS arm64 and Linux x86_64 and aarch64, pnpm 10-12 and Bun 1.4, the hermetic registry, nightly canary, performance budgets | 1-2 weeks / 2-4 days |
| E: migration and release | remove the registry, migrate codaset, platform and london, README section and the two guides | 1-2 weeks / 2-4 days |
| **Total** | | **6-10 weeks / 10-18 days** |

The earlier 9-15 engineer-weeks included npm, Windows hosts and a compiled CLI, all now out of v1.
