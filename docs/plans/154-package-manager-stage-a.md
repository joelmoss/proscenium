# #154 Stage A results

Evidence for the Stage A pilot of [the package manager plan](154-package-manager.md#stage-a-execution-contract).
Each leg records its commands, tool versions, revisions and verdicts. Legs that run against the
maintainer's private checkouts (london, hue) record no source or manifest contents, only what is
needed to repeat the run.

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
