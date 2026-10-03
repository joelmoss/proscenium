# Proscenium next generation package manager engineering specification

Research date: 3 October 2026. Repository baseline: `joelmoss/proscenium` at `b3c795745ceb6f4810d41283616dee61865834d9` on `master`.

Status: researched design specification with a confirmed asset-serving boundary and an unproven dependency-bridge representation. Proscenium MUST serve frontend files from the installed Ruby gem using its existing functionality. This document specifies proposed package-manager behavior; neither the dependency-only bridge nor the full conformance suite has been implemented. MUST, SHOULD, and MAY describe requirements. Repository observations, documentation findings, local experiments, and proposed decisions are identified separately.

Tracking issue: [#154](https://github.com/joelmoss/proscenium/issues/154). This document is the only copy of the plan. The issue tracks stage status and records maintainer sign-off; it does not restate the plan.

Revised 3 October 2026 after a scope review: v1 supports npm, pnpm and Bun only (Yarn is out); the premise that the registry is unused is corrected; real consumers and their gems are named as acceptance cases. See [Known consumers and real-gem findings](#known-consumers-and-real-gem-findings).

## Motivation

**Gem-first installation.** Adding a gem with frontend code and a package.json should make its JS dependencies installable through one coordinated command. Authors keep declarations with their code; apps need not duplicate each gem's dependency list or publish its assets to npm. Gems without a manifest retain existing serving and app-provided dependencies.

**One version pin, not two.** Today an app that uses a gem's JS pins the gem twice: once in Gemfile.lock and again in package.json (a `github:` URL or a registry version). The two pins have drifted in practice (hue, below). The bridge makes Gemfile.lock the only pin for the gem; package.json pins only ordinary JS packages.

**Native compatibility.** The original workspace proposal aimed to avoid emulating Bundler and the JS resolvers. Preserve native manifests, locks, monorepos and dependency/peer/optional/platform/script behavior. Separate gem contexts prevent dependency flattening; native root-lock integration avoids a second shadow graph.

**Existing asset serving.** Proscenium already serves installed-gem files. Only dependency installation and lookup need extending. Copying would add another source location and synchronization state. Preserve @rubygems imports, relative paths and stable URLs; generated contexts contain metadata only.

**Registry-free installs.** Installs must work with Rails stopped, without scoped-registry setup or a hosted registry service. This removes the current fixture's running-app installation dependency while retaining the distinct RubyGems serving middleware.

**Speed and polished DX.** Go is the settled CLI language for low overhead; performance still requires measurement. Prebuilt binaries in the existing gem support users who add the gem first, without another CLI install or Go compiler. Automatic detection, idempotent setup and bin/proscenium install keep daily use familiar.

**Evidence before commitment.** Stage A must prove original-source lookup, portable locks, native peer policy and shared React identity for each v1 manager before a representation is adopted. Failed adapters remain unqualified; copied assets, registry shims and silent graph changes are excluded fallbacks.

## Known consumers and real-gem findings

Checked 3 October 2026 against the maintainer's own apps. No consumer outside these apps is known; outside gem authors are the intended audience, which makes the gem author contract and guide v1 deliverables rather than follow-ups.

| App | Manager | Gem JS dependency today | Problem |
|---|---|---|---|
| codaset | Bun (`bun.lock`) | `@rubygems/proscenium-ui ^0.2.1` from the hosted registry `registry.proscenium.rocks`, set as the `@rubygems` scope registry in `.npmrc` | Depends on a network service. That service is not this repository's engine registry controller (its tarball URLs are `/tarballs/<gem>/<version>.tgz`, not `/registry/@rubygems/:gem/-/:file`). The maintainer runs it and retires it once this feature lands; there is no external deadline. |
| platform | pnpm | `@rubygems/hue` as `github:harleytherapy/hue#<sha>` | Second pin of the same gem; has drifted from Gemfile.lock in practice. |
| london | pnpm | `@rubygems/hue` as `github:harleytherapy/hue#<sha>` | Same double pin. Its `.npmrc` keeps the in-app registry (`registry.proscenium.test:3001`) commented out: that route was tried and abandoned. |

So the premise "the registry is unused" holds for the engine's `RegistryController` only. The hosted registry is in use by codaset, and replacing it is part of this feature's acceptance, not a fixture cleanup.

Findings from the real gems, which Stage A uses as fixtures alongside the synthetic ones:

- **Both gems are Git sources** (`remote: https://github.com/...` in each app's Gemfile.lock). Bundler installs a Git gem as a full checkout, so package.json is on disk even though hue's `spec.files` (`{app,config,db,exe,lib,bin}/**/*` plus three files) does not include it. The same hue release built as a `.gem` would ship without its manifest and could not participate. Discovery must work for Git checkouts, and `proscenium gem check` must catch the missing-from-`spec.files` case before a gem is released to rubygems.org.
- **Manifest versions are unreliable.** hue's current package.json has no `version` at all; older installed checkouts say `0.2.3` while the gem is `0.5.3`. proscenium-ui's package.json says `0.2.0` while `Proscenium::UI::VERSION` is `0.2.1`, and codaset's lock resolves `0.2.1`, so the hosted registry already ignores the manifest version. The original rule, that a missing or invalid manifest version is a participation error, would have rejected hue outright. Decision D1 (settled, see [Research limits and remaining decisions](#research-limits-and-remaining-decisions)) removes the dependency on the manifest version.
- **hue declares `react` and `react-dom` as `dependencies`, not `peerDependencies`.** In a separate dependency context that can give hue its own React copy, a second React instance next to the app's. This is the C12/C13 risk in a real gem rather than a synthetic one. Stage A must show what each manager does with it; the likely outcome is an author-contract diagnostic ("declare React as a peer"), not bridge magic.
- **Both gems use `github:` dependencies** (`sourdough-toast`). Git URL dependencies inside a gem manifest are a v1 case (C10), not an edge case.

## Decision and product contract

Implement the Proscenium package-manager CLI in Go for fast startup, bounded parallel metadata work, and low orchestration overhead. Package it with the existing Proscenium gem. Native Bundler continues to own Ruby resolution/installation, including gem frontend files. npm, pnpm, or Bun owns JS dependency resolution, installation, lifecycle policy, and native locks. Yarn is not supported in v1. The Go CLI discovers dependency declarations using authoritative Bundler metadata and associates each participating gem with a native JS dependency context; it does not reimplement either ecosystem's solver.

Frontend assets MUST remain in the directory where Bundler installed the gem. Proscenium MUST rely on its current gem asset-serving functionality; it MUST NOT copy, relocate, extract, or mirror frontend asset trees to make this package-manager feature work. The candidate bridge uses project-local, dependency-only workspace manifests. These are generated installation metadata, not copies of the gem's frontend package. This representation requires feasibility testing across all three v1 managers. The feature replaces both the unused engine registry controller and the hosted registry codaset uses today, and requires no Rails registry server, hosted registry, special scoped registry setup, or npm publication of gem assets.

Preserving `Gemfile`, gemspec, and `package.json` means preserving native formats, authority, and editing workflow. Routine installs MUST leave user manifests unchanged. First non-frozen installation may perform one-time, idempotent bridge registration and add an owned project launcher, with exact edits reported; later installs do not repeat those manifest edits. Preserve all unrelated declarations, scripts, overrides, workspace patterns, and lock semantics. Existing Proscenium gem imports remain the asset API; dependency contexts do not expose ordinary native gem packages.

This qualification is essential: a fully transparent workspace that makes no root workspace configuration changes is not established by the research. If “preserve” instead means that every root manifest must remain byte-for-byte unchanged even at initialization, the proposed integrated workspace design does not satisfy that stronger constraint. Do not hide temporary manifest edits, silently run a second graph, or label such an arrangement native root-lockfile compatibility.

The user-facing workflow is Gemfile-first: add Proscenium normally, run bundle install, then bundle exec proscenium install once. First installation handles bridge registration and creates the project launcher. Thereafter use bin/proscenium install to coordinate Ruby and JS dependencies, including after Gemfile changes. Defaults use existing native manager signals and require no separate CLI installation or hand-written settings. Normal native commands remain supported. Rails boot and asset requests never install dependencies or contact registries.

Primary users are Rails developers consuming gems with frontend dependencies, gem authors shipping frontend components, and deployment systems installing the same application on different hosts. Success means a fresh checkout installs JavaScript dependencies and serves the gem's JS/CSS directly from its installed location without a running Rails server or registry shim, using committed native lockfiles. Concretely: codaset, platform and london each install from a fresh checkout with no hosted registry and no `github:` pin for a gem, and each gem's version is pinned only in Gemfile.lock.

## Verified repository architecture

The current repository is a Rails frontend engine and compiler, rather than an independent package resolver. The Ruby layer integrates with Rails, Rack, ActionView, asset manifests, and helpers. A Go shared library uses an esbuild fork and is called through FFI. The package-manager feature should extend this architecture without replacing its asset engine.

| Existing component | Observed behavior | Consequence for this specification |
|---|---|---|
| `lib/proscenium/bundled_gems.rb:7` | Uses `Bundler.load.specs`, sorted by gem name; maps gems to installed roots. Proscenium itself maps to `lib/proscenium`. | Reuse Bundler as authority. Bridge discovery needs the actual gem root, not the special asset root. |
| `lib/proscenium/builder.rb:218`, `main.go`, `internal/types/types.go` | Passes RubyGems root mapping and build configuration through the FFI boundary. | Add dependency-context mapping separately from existing gem asset roots. Preserve existing C entry points where possible. |
| `internal/plugin/bundler.go:311` | A gem's bare import resolves using the installed `node_modules/@rubygems/<gem>` real path when present; otherwise falls back to the app root. | Use explicit native dependency context for participating gems; preserve the current app-context fallback for gems without a manifest. |
| `internal/resolver/resolve.go:147` | Resolve-only builds preserve symlinks, use environment plus `proscenium` conditions, and prioritize `module`, `browser`, then `main`. | Installation parity and browser module-resolution parity are different contracts. Preserve the current browser conditions. |
| `lib/proscenium/resolver.rb`, `internal/utils/utils.go` | Maintains real filesystem and virtual URL paths, including `@rubygems` gem addressing. | Keep installed gem roots and existing virtual URL mapping. No copied-source or reverse-copy mapping is introduced. |
| `lib/proscenium/railtie.rb`, middleware, side-loading and importer | Configures on-demand bundling, side-loading, helpers, manifest loading, and precompilation tasks. | No Rails boot requirement for installation. Preserve bundled and unbundled asset behavior. |
| `app/controllers/proscenium/registry_controller.rb:94` | Serves a packument for the installed gem version only; advertises `dependencies`. | It is a registry compatibility path, not a general resolver. Peers and optional dependencies are not included in that packument. |
| Registry controller at lines 163 and 191 | Deterministic tarball contains only `package/package.json`; uses the gem's manifest bytes, or synthesizes a minimal manifest. | Existing npm package contents do not themselves expose the gem's JS/CSS. The asset resolver supplies those separately. |
| `config/routes.rb`, registry controller tests | Provides metadata and tarball routes with installed-version checks and strict JSON validation. | Replace this unused install path directly; translate useful validation cases into bridge tests. |
| `fixtures/dummy/package.json` | Pins pnpm 10.4.0 and contains `@rubygems/gem_npm` and `@rubygems/gem_npm_ext`, plus file/link packages. | Current fixtures do not validate pnpm 12.7 behavior. They provide valuable migration cases. |
| `.github/workflows/main.yml:191` | Says fixture `node_modules` is committed because clean registry-backed installation needs the app running. | A clean registry-free install in CI is a concrete acceptance criterion. |
| `lib/proscenium/runtime/` | Bun testing uses a Rails daemon, middleware, and a Bun plugin; daemon disables code splitting for the harness. | Bun as an installer and Bun as a test runner are separate integrations. Test both. |
| `proscenium.gemspec`, `Rakefile:50` | Ruby >=3.4, RubyGems >=3.3.22, Rails >=7.2 and <9; ffi ~>1.17; json >=2.20 and <3. Platform build list is centralized. | Keep current compatibility bounds unless a separately justified change expands them. |

Current platform packages cover Intel/ARM macOS, x86_64/aarch64 glibc Linux, and x64 Windows UCRT. The repository explicitly excludes musl for its current Go C-shared/FFI architecture. The package orchestration layer can be portable without promising that the existing asset engine runs on Alpine.

The evidence above was read from a fresh clone, not inferred from the README alone. The current Ruby/Go/Bun integration suites and release artifacts were not executed during this research. Existing CI configuration describes intended coverage; it is not proof that this checkout passes.

[Pinned repository tree](https://github.com/joelmoss/proscenium/tree/b3c795745ceb6f4810d41283616dee61865834d9). [Registry implementation](https://github.com/joelmoss/proscenium/blob/b3c795745ceb6f4810d41283616dee61865834d9/app/controllers/proscenium/registry_controller.rb#L94). [Gem import context](https://github.com/joelmoss/proscenium/blob/b3c795745ceb6f4810d41283616dee61865834d9/internal/plugin/bundler.go#L311).

## Discussion assumptions verified

| Assumption | Finding | Decision |
|---|---|---|
| Gem frontend files need copying to join JavaScript dependency installation. | Current Proscenium already reads assets from installed gem roots. The maintainer requires that behavior to remain authoritative. | Do not copy frontend assets; evaluate dependency-only metadata contexts. |
| Gems need a package.json to serve frontend assets. | Existing gem asset serving works independently of dependency-manifest discovery. | No-manifest gems keep existing behavior and contribute no automatic JS dependency declarations. |
| Native managers can install workspace dependency graphs. | Official documentation and basic local full-package fixtures support the general mechanism. | Dependency-only workspaces are a candidate; those fixtures do not prove original-gem source resolution. |
| One package.json.workspaces field covers pnpm. | pnpm 12.7 can create YAML if absent; existing YAML remains authoritative. The repo uses pnpm 10.x. | Use a pnpm adapter and explicitly register candidate contexts in YAML. |
| A metadata-only workspace exposes the gem's frontend package to ordinary JS tools. | It has no frontend files or entry points. | Ordinary native package-name imports of the gem are outside v1; use existing Proscenium gem imports. |
| Root hoisting supplies every gem's dependencies. | Local pnpm and Bun probes falsify universal root-import availability. | Associate each gem with its own native installation context; preserve distinct dependency graphs. |
| Direct workspace registration at the installed gem root is universally portable. | External roots, absolute lock paths, read-only gems, and native writes remain unproven. | Prototype only if installed gems remain unchanged and committed inputs remain portable. |
| Native delegation gives identical behavior across managers. | Linkers, peer policy, scripts, and lock formats differ. | Match each manager against its own baseline, never require equal trees. |
| Yarn workspaces guarantee current Go resolver compatibility. | PnP and other linkers require separate loader integration. | Superseded: Yarn is out of v1 entirely (no known user); a Yarn project gets an unsupported error before any write. |
| Keeping source in the gem guarantees one React instance. | Source location alone does not establish peer placement or shared module identity. | Test app/gem React identity and native peer diagnostics explicitly. |

Maintainer requirements: the engine registry controller is unused and is replaced directly; the hosted registry codaset uses is retired once this feature lands (see [Known consumers](#known-consumers-and-real-gem-findings)). v1 supports npm, pnpm and Bun. Frontend files are served from the installed Ruby gem through existing Proscenium functionality. A gem with a valid package manifest participates in automatic JavaScript dependency installation; a gem without a manifest retains current asset serving and app-level dependency lookup.

The available referenced chat included the workspace proposal, its five prototype questions, and the final brief. The thread tool exposed five turns and no older cursor, so no unseen earlier decisions are treated as established requirements.

### Local feasibility evidence

On macOS ARM64, a fixture contained two normal workspace packages: `@rubygems/widget` imported `probe-leaf`, both at 1.0.0. The root registered `packages/*` and declared neither package as a dependency. pnpm also had YAML with `linkWorkspacePackages: true`; Yarn used `nodeLinker: node-modules`. These were local-only installs, with lifecycle execution disabled. Node v25.9.0 performed CommonJS import probes.

| Manager actually tested | Install | Load widget by relative workspace path | Import widget by name at app root | Frozen reinstall |
|---|---|---|---|---|
| npm 11.12.1 | Passed | 42 | 42 | `npm ci` passed; lock bytes unchanged |
| pnpm 10.34.4 | Passed | 42 | MODULE_NOT_FOUND | Frozen install passed; lock bytes unchanged |
| Yarn 3.6.0, node-modules | Passed | 42 | 42 | Immutable install passed; lock bytes unchanged |
| Bun 1.4.2, fresh workspace defaults | Passed | 42 | MODULE_NOT_FOUND | Frozen install passed; byte comparison not recorded |

These earlier probes establish a narrow full-package workspace mechanism and falsify the universal root-linking assumption. Their fixture included frontend files inside the workspaces. They do NOT verify the revised dependency-only bridge or compilation of source left in an installed gem. They also do not establish registry fetching, peer placement, existing-lock migration, lifecycle behavior, PnP, CSS/exports, Gemfile discovery, Windows, Linux, or actual Proscenium asset integration. npm and Yarn hoisting in this fixture is not a guaranteed application API.

[pnpm workspace contract](https://pnpm.io/workspaces). [npm workspaces](https://docs.npmjs.com/cli/using-npm/workspaces/). [Yarn install modes](https://yarnpkg.com/features/linkers). [Bun isolated installs](https://bun.sh/docs/pm/isolated-installs).

### Version probes (3 October 2026)

Scratch probes, not Stage A evidence: macOS ARM64, offline installs, an app whose root `workspaces` (and pnpm YAML) registers `.proscenium/packages/*`, holding one empty context `@rubygems/hue`. They settle D1 and the Bun floor; Stage A repeats them against real installed gems.

Context referenced from the app as `workspace:*`:

| Context `version` | npm 10.9.9, 11.6.2, 11.12.1, 12.2.0 | pnpm 10.18.1, 10.34.4, 11.0.0 | pnpm 12.8.1 | Bun 1.3.0, 1.3.13, 1.3.14 | Bun 1.4.0, 1.4.2 |
|---|---|---|---|---|---|
| omitted | links | links | links | fails: workspace not found | links |
| `0.5.3.pre1` (Ruby prerelease) | links | fails: `ERR_PNPM_NO_MATCHING_VERSION_INSIDE_WORKSPACE` | links | fails: workspace not found | links |
| `0.5.3` | links | links | links | fails: workspace not found | links |

Bun 1.3.x links the same context when it lives in a directory without a leading dot (`gems/*`), so the failure is dot-directory discovery, fixed in 1.4.0.

Context referenced from the app by semver range `^0.5.0` (npm 12.2.0, pnpm 12.8.1, Bun 1.4.2):

| Context `version` | npm | pnpm | Bun |
|---|---|---|---|
| `0.5.3` | links | requests `@rubygems/hue` from the registry | links |
| omitted | links | requests it from the registry | requests it from the registry (404) |

A range reference therefore reaches the public npm registry on pnpm always and on Bun when the version does not match. Nobody publishes `@rubygems/hue` there today; if anyone did, it would install silently. Hence D1's local-link rule and C44.

### Fresh-checkout probes (3 October 2026)

What happens when someone runs the package manager directly instead of `bin/proscenium install`. Setup: lock created with two contexts under `.proscenium/packages/`, then `.proscenium/` removed to mimic a fresh checkout of a project that ignores it. npm 12.2.0, pnpm 12.8.1, Bun 1.4.2, offline.

| Native command on the fresh checkout | npm | pnpm | Bun |
|---|---|---|---|
| frozen (`npm ci`, `--frozen-lockfile`) | exit 0, contexts' dependencies not installed, no error | fails: `ERR_PNPM_OUTDATED_LOCKFILE` | exit 0, note only: "skipped 2 workspaces listed in bun.lock but not on disk" |
| plain install | exit 0, lockfile rewritten without the contexts | exit 0, lockfile rewritten without the contexts | exit 0, "2 packages removed", lockfile rewritten |

So with ignored metadata, two of three managers install silently incomplete, and a plain install produces a lockfile that drops every gem's dependencies for whoever commits it. Committing the metadata removes the precondition.

The `workspace:` protocol in npm, measured on 10.9.9, 11.6.2 and 12.2.0: accepted in the root package.json, rejected with `EUNSUPPORTEDPROTOCOL` in a workspace package's dependencies. Generated contexts are workspace packages, so npm needs `*`.

### Layout probes (3 October 2026)

Where each manager puts a gem context's dependencies, and what resolves from where. npm 12.2.0, pnpm 12.8.1, Bun 1.4.2 with default settings; the app depends on `is-number@6.0.0` and `react@18.3.1`; the context `@rubygems/hue` depends on `is-number@7.0.0` and `is-odd@3.0.1` and declares `react@^18.3.1` as a peer. Node's `require.resolve`, not Proscenium's resolver.

| | npm | pnpm | Bun |
|---|---|---|---|
| App's `is-number@6` | `node_modules/is-number`, real folder | link into `node_modules/.pnpm/` | link into `node_modules/.bun/` |
| Context's `is-number@7` | real folder in `.proscenium/packages/hue/node_modules/` | link there, into `.pnpm/` | link there, into `.bun/` |
| Context-only `is-odd` | hoisted to the root `node_modules` | under the context only | under the context only |
| Resolved from the context | 7.0.0, is-odd found | 7.0.0, is-odd found | 7.0.0, is-odd found |
| Resolved from the app root | 6.0.0, is-odd found | 6.0.0, `MODULE_NOT_FOUND` | 6.0.0, `MODULE_NOT_FOUND` |
| React from app and from context | same real file | same real file (two link paths) | same real file (two link paths) |

## Scope and compatibility policy

V1 includes orchestration, gem discovery, one dependency manifest per participating gem, dependency-only metadata projection, candidate workspace registration, native locking, descriptor provenance, dependency lookup integration, inspection, adoption, reproducible CI installation, `proscenium gem check`, and a gem author guide. Existing gem asset serving is reused for gems with and without manifests. The three managers (npm, pnpm, Bun) are independent adapters with independent qualification status.

V1 excludes copying or mirroring gem frontend files, turning gems into complete native JavaScript packages, a new Ruby resolver, a new JS resolver, registry proxying, cross-manager lockfile conversion, package publishing, downloading runtimes without explicit project policy, implicit gem frontend builds, Yarn in every version and linker mode (including Plug'n'Play), and multiple dependency manifests inside one gem. It does not expand the current asset engine's platform support.

| Family | Proposed qualification target | Shipping rule |
|---|---|---|
| Bundler | Repo's supported Ruby 3.4 baseline and Ruby 4.0; Bundler version selected by project tooling/lock contract | Test frozen config and group/platform discovery on each qualified version. Do not silently upgrade it. |
| npm | Lines 10.9.x, 11.x and 12.x (as of 3 October 2026) | npm releases only its latest major (12); security fixes go to any npm bundled with a Node.js still in maintenance: 10.9.x with Node 22 (until 2027-04-30), 11.x with Node 24 and 26. Test each line at its newest patch; the 10.x leg also at its oldest supported patch. |
| pnpm | Lines 10.x, 11.x and 12.x (as of 3 October 2026) | 12 is active; 10 and 11 reach end of life on 2027-04-30. Test each line at its newest patch; maintain YAML workspace support throughout. |
| Bun | 1.4.x only (as of 3 October 2026) | Bun publishes no support policy and releases only its latest version (no 1.3.x release after 1.4.0 on 2026-08-20). Minimum 1.4.0: Bun 1.3.x does not discover workspaces under a dot directory such as `.proscenium/packages`. Qualify hoisted and isolated installs independently. Preserve existing lock configuration. |
| Node.js | 22, 24 and 26 | Supported LTS/current lines only. Node 25 reached end of life on 2026-06-01. npm 12 needs `^22.22.2 \|\| ^24.15.0 \|\| >=26.0.0`. |

**Support rule.** Proscenium supports exactly the package-manager and Node.js release lines their owners still maintain at the time of each Proscenium release, tested at each line's newest patch, plus the oldest version of the oldest supported line so the adapter can enforce a floor. A line that its owner drops is dropped at the next Proscenium release. The table above is a dated snapshot; the machine-readable adapter capability table is the source of truth and is regenerated per release. The repository's own pins were outside this rule (CI on Bun 1.3.13, fixtures on pnpm 10.4.0 and 10.6.0); #155 raises them to Bun 1.4.2 and pnpm 10.34.6. Moving the fixtures to pnpm 12 waits for this feature: pnpm 12 records itself in the lockfile, and regenerating `fixtures/dummy`'s lock needs the dummy app's own registry running.

These are targets, not promises of already verified compatibility. Exact supported versions belong in a machine-readable adapter capability table committed with release tests. Unsupported versions produce an actionable error, with an explicitly labeled experimental override for development only. Experimental overrides MUST be rejected by `--frozen` CI until qualified. Yarn has no adapter and no experimental override: a project selecting Yarn (packageManager field, yarn.lock or .yarnrc.yml) gets an unsupported-manager error (exit 3) before any write. Adding Yarn later is a new adapter with its own Stage A evidence, not a flag.

Manager selection: use an explicit override when supplied; otherwise the root packageManager field; otherwise exactly one recognized native lockfile. Infer this without a setup prompt when unambiguous. Conflicting signals or multiple lockfiles produce an actionable error. A project with no manager signal must make one explicit choice; interactive setup may offer it, while CI requires an explicit selection. Persist ordinary manager/version selection in native configuration where applicable instead of duplicating it in Proscenium settings. Account for npm shrinkwrap precedence and preserve Corepack/mise/Volta policy; never choose a different manager merely because it is installed.

## Architecture and persistent artifacts

The install order is Ruby installation, gem dependency-manifest discovery, generation of dependency-only bridge metadata, native JS installation, dependency-context validation, then successful local state commit. Gem assets remain at Bundler's installed roots throughout. JS changes do not cause Ruby re-resolution. An updated gem may change its JS dependencies, so Ruby graph changes must be followed by dependency synchronization before builds.

```text
Gemfile + gemspec + Gemfile.lock
               |
          native Bundler
               |
        installed Ruby gems
          /             \
frontend files       package.json, when present
stay in gem root             |
          |         dependency-only metadata contexts
          |         .proscenium/packages/<gem>/package.json
          |                  |
          |         root native workspace registration
          |         + app package.json
          |                  |
          |            npm / pnpm / Bun
          |                  |
          |          native JS lock + dependency layout
          |                  |
existing Proscenium asset engine <- gem dependency-context map
               |
       current stable asset URLs

No package.json: existing asset serving + app dependency context.
```

| Artifact | Ownership | Commit policy |
|---|---|---|
| Gemfile, gemspec, Gemfile.lock | User and Bundler | Normal project policy; no Proscenium Ruby lock serialization |
| Installed gem frontend files and package.json | Bundler/gem author | Read in place; no Proscenium copies or writes |
| Root package.json and existing workspace manifests | User and native manager | Commit; bridge edits limited to owned initialization entries and explicit add/remove commands |
| pnpm-workspace.yaml / native manager config | User and native manager | Commit candidate bridge registration; preserve unrelated policy |
| Native npm/pnpm/Bun lockfile | Selected native manager | Commit; no implicit format conversion |
| proscenium.json | Optional advanced bridge settings | Absent with defaults; commit explicit overrides only; no dependency declarations |
| proscenium.bridge.json | Candidate generated descriptor receipt | Retain only if feasibility proves a need; if required, commit it without hand editing; no frontend inventory or JS transitive graph |
| .proscenium/packages/<gem>/package.json | Candidate dependency-only workspace metadata | **Commit.** Written byte-stable (fixed key order, trailing newline, no timestamps or host paths) so an unchanged gem never churns it. Committing it lets a plain native install on a fresh checkout see every gem (see [Fresh-checkout probes](#fresh-checkout-probes-3-october-2026)), and puts a gem upgrade's JS dependency changes in the pull request. No frontend asset files. |
| Packaged Go CLI binary + exe/proscenium | Platform gem release artifacts + tiny RubyGems launcher | Distributed with the existing gem; binary version matches gem version; no user compiler/download step |
| bin/proscenium | Generated project launcher | Commit; preserve user files; start selected Go binary when available, bootstrap native Ruby installation only when needed |
| .proscenium/state.json, map.json, journal and process lock | Machine-local generated state | Ignore (the generated ignore rule covers `.proscenium/*` except `.proscenium/packages/`); committed provenance contains no installed absolute paths |

Candidate dependency-context paths are stable and project-relative. They contain gem identity, never machine-specific installation prefixes, platform names, or random hashes. Native managers own any dependency files and links they create there. Proscenium writes only generated metadata and state; it does not populate these contexts with gem frontend files.

Optional advanced settings example. Defaults derive manager selection from native configuration, discover all Gemfile groups independently of BUNDLE_WITHOUT, and use declared Gemfile.lock platforms. Generate no proscenium.json when defaults suffice. Explicit group/platform/name overrides remain available without duplicating dependency declarations:

```json
{
  "schema": 1,
  "bridge": {
    "directory": ".proscenium/packages",
    "projection": "dependency-context-v1"
  },
  "rubyGroups": ["default", "development", "test"],
  "platforms": ["arm64-darwin", "x86_64-linux-gnu", "x64-mingw-ucrt"],
  "gemOverrides": {}
}
```

When explicitly configured, `rubyGroups` overrides the default discovery of all Gemfile groups. The discovery universe remains independent of BUNDLE_WITHOUT and does not change what Bundler installs. Platforms default to the native Ruby lock's declared set, with explicit overrides where needed. Production may omit Ruby gems while reproducing their locked dependency descriptors. Discovery reads only manifest metadata from installed sources or matching locked archives, without loading extensions or extracting frontend trees. Omitted gems do not become asset-servable; offline mode fails if required descriptor metadata is unavailable.

Proposed generated descriptor receipt, with illustrative digest placeholders. Proscenium maintains it; developers commit it with native locks:

```json
{
  "schema": 1,
  "projection": "dependency-context-v1",
  "packages": [{
    "gem": "widgets",
    "rubyVersion": "2.0.0.pre",
    "source": { "type": "git", "revision": "<full revision>" },
    "contextName": "@rubygems/widgets",
    "context": ".proscenium/packages/widgets",
    "sourceManifestSha256": "<digest>",
    "dependencyManifestSha256": "<digest>"
  }]
}
```

Source identity MUST bind to Gemfile.lock's source and revision. Record credential-free source identifiers, declared platform variants, and native gem checksum evidence when available. Hash original manifest bytes and deterministic dependency-only metadata. Installed absolute roots remain local state. There is no frontend tree digest, copied-file inventory, or copied payload in this receipt. Bundler remains responsible for gem source installation and integrity.

The proposed `proscenium.bridge.json` receipt binds gem source identity and dependency-manifest transformations to native JS lock inputs. It selects no transitive versions. Frozen installation compares current descriptors with that receipt because native workspace locks may not integrity-pin local manifest contents. Its necessity and minimal schema must be validated during Stage A; committed context metadata that records the source manifest hash may make it redundant; remove redundant fields where native locks already provide the required evidence. Changes only to frontend asset files do not require rewriting the bridge receipt.

## Gem author contract and dependency metadata

Discovery reads a root `package.json` from each gem in the configured locked universe. An optional gemspec metadata string `proscenium.frontend_root` MAY select the relative directory containing the manifest; it MUST resolve inside the gem. It does not move files or redefine existing asset-serving roots.

A valid manifest contributes declared runtime, optional, and peer dependencies to the native JS installation step. A gem without a manifest generates no dependency workspace, contributes no automatic JS dependency declarations, and retains existing Proscenium asset serving and app dependency lookup. Self-contained frontend files work without a manifest. External imports must be supplied by the app's own package.json. Do not synthesize an empty package for such gems. A present but invalid or unreadable manifest is an actionable installation error.

Authors include frontend files and any dependency manifest in the built gem's `spec.files`. Bundler installs them together; Proscenium serves the files in place. A manifest present only in the source checkout but missing from the built gem cannot drive automatic consumer installation. Git-source gems are the exception: Bundler installs them as full checkouts, so their manifest is on disk whatever `spec.files` says. Discovery reads the installed root in both cases, and `gem check` warns when a manifest would be lost from the built gem. `proscenium gem check` checks built archives and source layout without unpacking frontend assets into a bridge or executing author builds.

The candidate native dependency-context name is `@rubygems/<gem-name>` and must be valid under the selected manager. This is an internal graph identity, not a promise of an importable gem package for native JS tools. Explicit name overrides are recorded and validated against collisions. Per decision D1, the generated context omits `version`: the gem's manifest version is neither required nor copied, so a missing or stale one (hue, proscenium-ui) is not an error, and a Ruby version is never written there (pnpm 10 and 11 reject Ruby prerelease syntax such as `0.5.3.pre1`). Every reference Proscenium generates to a context uses the adapter's local-link syntax: `workspace:*` for pnpm and Bun, `*` for npm, which rejects `workspace:` inside a workspace package on every supported line (`EUNSUPPORTEDPROTOCOL`) but always links a workspace package whatever the range says. A missing or invalid context name is still a participation error.

The proposed `dependency-context-v1` projection generates installation metadata only: the context name (no `version`, per D1), `private: true`, runtime `dependencies`, `peerDependencies`, `peerDependenciesMeta`, `optionalDependencies`, and qualified engine/OS/CPU/libc constraints. Exclude gem-author devDependencies, lifecycle/task scripts, nested workspaces, and nested packageManager selection. Do not expose main/module/browser, exports/imports, types, bin, sideEffects, or files as pointers to nonexistent workspace assets. The original package.json stays in the gem for the existing asset engine's applicable lookup behavior. Inspect reports every projection rule; Stage A compares this explicit consumer graph with a native baseline.

App-level overrides, resolutions, patches, catalogs, and script approvals remain authoritative. A gem cannot promote its own install policy into the app. Reject nested workspace declarations for v1 with a clear participation error. Unknown source metadata remains inert data and is not automatically copied into executable bridge policy.

Proscenium MUST NOT run gem frontend installation/build hooks. The candidate dependency-only manifest contains no scripts or binding.gyp, and no frontend source is placed in its directory. For v1, a gem declaring required install/prepare hooks or implicit native frontend builds receives an author-contract error rather than silently receiving an incomplete build. Assets needed by consumers must already ship in the gem. Native third-party JS dependency scripts follow the selected manager's app-level policy; this is a separate trust boundary.

Relative `file:`/`link:` dependencies are a feasibility boundary for dependency-only contexts: relocating metadata changes their base directory. V1 MUST reject these references unless an adapter proves native installation directly from the original contained target, portable lock representation, and no Proscenium asset copying or installed-gem writes. Do not silently rewrite them into host-specific absolute paths. A gem's manifest may reference another gem's context (`@rubygems/<other>`, as a dependency or peer) only when `<other>` is a runtime dependency in that gem's gemspec. Bundler metadata says whether it is. That makes Bundler the single authority for gem-to-gem compatibility: `<other>` is guaranteed to be in the locked universe with a context of its own, and its version is already checked against the gemspec constraint by Bundler's resolution. The JS-side range is therefore dropped, not translated (contexts carry no version, per D1), and the reference is rewritten to the adapter's local-link syntax. The exception is an optional peer (`peerDependenciesMeta.<name>.optional`), which a gemspec cannot express because a runtime dependency is always installed: when the other gem is in the locked universe it is linked the same way, and when it is not, the peer entry is left out of the projection, which is what native optional-peer handling would produce for an absent provider. Bundler does not check an optional peer's version, so `inspect` and `doctor` show its declared range beside the other gem's locked version. Any other reference to a gem that is not a gemspec runtime dependency, or that has no context, is a participation error naming both gems and the gemspec line to add. It is never rewritten, because npm would satisfy `*` for a missing workspace package from the public registry. Cross-gem declarations must never fetch a gem-backed package from a registry. Unsupported protocols receive actionable diagnostics.

Asset delivery remains entirely with the existing Proscenium gem resolver and serving middleware. No frontend files, CSS, images, fonts, type declarations, source maps, or gem package entry points are copied or linked into a generated workspace by this feature. npm publish `files` filters do not change which gem files the existing engine may serve.

Candidate context generation writes a small JSON manifest into a staged project-local directory, then commits it at the stable context path. Do not copy frontend trees, create façade source files, or add generated node_modules inside an installed gem. Shared and read-only gem installations must remain untouched. Metadata path containment, collision checks, and safe atomic writes still apply.

[RubyGems specification and packaged file contract](https://guides.rubygems.org/specification-reference/). [Node package entry points and exports](https://nodejs.org/api/packages.html). [npm package manifest fields](https://docs.npmjs.com/cli/v12/configuring-npm/package-json/).

## Workspace bridge feasibility and alternatives

| Strategy | Native dependency graph and lock integration | Asset-serving boundary and portability | Disposition |
|---|---|---|---|
| Generated dependency-only workspace manifests | Candidate stable project-relative native inputs; each gem retains its own graph context | Proscenium serves original installed-gem files; issuer lookup, peers, and local file dependencies need proof | Primary Stage A hypothesis, not yet verified. |
| Direct workspace at installed gem path | Depends on external workspace recognition and portable locked paths | Assets stay in gem; native writes to shared/read-only roots may violate the contract | Prototype comparison only; reject if it writes to gem roots or commits host paths. |
| Metadata-only local file/tarball descriptor | May provide alternate native consumer semantics and peer placement | Contains only dependency metadata, never gem frontend payload | Conditional fallback candidate; must prove locks, context lookup, and portability. |
| Copied frontend workspace or source façade | Could expose a complete package to native JS tools | Duplicates or mirrors assets and changes their source location | Excluded by the confirmed requirement. |
| Shadow project or merged dependency manifest | Installs against a different graph; may flatten distinct contexts | Native root-lock, peer, script, and tooling behavior can diverge | Reject as silent fallback. |
| New registry shim or custom package resolver | Defeats native-manager/no-registry requirements | Adds a service or dependency resolver | Out of scope. |

Initialization adds `.proscenium/packages/*` to root `workspaces` for npm and Bun, preserving existing patterns and array/object form where supported. pnpm explicitly adds the same path to YAML `packages`; it preserves exclusions, catalogs, overrides, and build policy. If both JS and YAML workspace declarations exist, register dependency-only contexts consistently without pretending pnpm uses both. Existing exclusions or broad globs that include generated contexts twice must be diagnosed using the manager's own enumerated workspace set. Never remove exclusions silently.

App source addresses gem assets through existing Proscenium `@rubygems/<gem>/...` imports, regardless of whether the gem contributes a package manifest. The generated dependency context is not a complete importable JS package. Do not advertise direct Node/native-runner imports of gem assets or create app dependency edges solely to make those assets visible. Proscenium's Bun harness remains an engine-specific integration. Apps declare peer providers such as React in their own package.json when sharing is required; Stage A must prove that dependency-context attachment gives the required native peer placement.

Native workspace selection, transitive dependency resolution, peer diagnostics, optional omission, engine behavior, and linker configuration are preserved. Proscenium MUST NOT flatten all gem dependencies into the app's dependencies: this would lose distinct dependency and peer contexts.

Each adapter must prove dependency-context attachment to the root graph, package-local lookup without accidental hoisting, and any declared cross-gem local context edges. Plain semver linking depends on manager settings, including pnpm linkWorkspacePackages. Do not change global linking policy or silently fetch a gem-backed identity from npm. If peers or cross-gem graph semantics require explicit native edges, specify and test their purpose without claiming those edges expose frontend assets to ordinary JS tools.

Yarn is out of v1. If it is added later, note that its Plug'n'Play mode needs more than an adapter: the Yarn dependency-tree API, issuer-aware lookup, zip/unplugged file access, source-map support and stable virtual asset URLs in the asset engine. Silently forcing `nodeLinker: node-modules` would be prohibited.

[Bun workspace guide](https://bun.sh/guides/install/workspaces). [pnpm 12.7 release](https://pnpm.io/blog/releases/12.7).

## CLI contract

The CLI implementation is Go. Build a separate native executable from `cmd/proscenium/`; put orchestration, discovery coordination, metadata validation/generation, caching, journals, diagnostics, and native-manager adapters in Go packages. Keep this executable separate from the existing C-shared asset engine and do not load Rails, FFI, or the engine library during CLI execution.

Ship a matching prebuilt CLI binary inside each qualified platform Proscenium gem, under a dedicated directory such as `lib/proscenium/cli/proscenium` (`proscenium.exe` on Windows). RubyGems requires declared executables to be Ruby scripts, so `exe/proscenium` is only a small launcher that selects and starts the packaged Go binary, forwarding arguments, environment, output, signals, and exit status. It contains no package-manager implementation. [RubyGems executable contract](https://guides.rubygems.org/specification-reference/#executables).

Target `CGO_ENABLED=0` for the CLI and keep its imports independent of the C-shared engine. Build with the repository-pinned Go toolchain and reproducible release flags; qualify each supported OS/architecture. End users need no Go installation, compilation step, extra CLI gem, or binary download during normal installation. This is a build requirement, not an already verified artifact. [Go cgo build controls](https://pkg.go.dev/cmd/cgo).

Extend platform packaging to include the CLI binary as well as the engine library. Gate and clean both artifact directories explicitly: the platform-less gem MUST NOT accidentally contain the last platform's binary. Validate executable architecture, version, permissions, and file inventory in every built gem; an unsupported or missing binary produces an actionable error and never silently compiles or downloads a replacement.

The normal first-use workflow is: add Proscenium to the app's Gemfile, run `bundle install`, then run `bundle exec proscenium install`. No separate CLI gem, global installation, registry setup, or mandatory init command is required. On first successful installation, perform idempotent bridge setup and generate an owned project `bin/proscenium` launcher without overwriting an existing user file. Report all initial registration/launcher edits clearly.

The everyday command is bin/proscenium install. When the installed project-selected Go binary is available, the launcher starts it without booting Rails or requiring a complete Bundler setup. Go owns the install pipeline and invokes the native Ruby phase when needed. On a fresh checkout where Proscenium itself is not installed, the small committed launcher first invokes native Bundler, then locates and starts the selected packaged binary. Preserve frozen/offline/production guarantees during bootstrap; do not repair locked drift to load the CLI. Prototype missing-bundle, changed-Gemfile, and binary-selection behavior on every supported host. Measure Ruby/project launcher overhead separately from direct Go startup; do not add unconditional Ruby subprocess work to Go-only commands.

Keep package-manager selection automatic when existing configuration is unambiguous. Defaults require no hand-authored Proscenium settings. Advanced configuration and diagnostics remain available. Success output summarizes gem discovery and dependency installation; errors name the affected gem or dependency and give a specific corrective command. Repeated install is safe. Do not ask routine setup questions whose answers can be inferred from existing native manifests.

When native Ruby installation or update changes the selected Proscenium version, hand off to that version's packaged Go executable before continuing with incompatible CLI or descriptor schemas. Version the small launcher/helper handoff contract, preserve phase journal state, and prevent handoff loops. Qualify Windows process, cancellation, and in-use binary behavior as well as Unix relaunch. A separately distributed Go executable remains a future packaging option; Go is the settled implementation language regardless of distribution.

| Command | Contract and allowed writes |
|---|---|
| `proscenium init [--manager <name>]` | Optional explicit setup for advanced/adoption cases. Validate manager and show owned changes; defaults do not require this command. Create settings only for explicit overrides and a descriptor receipt only if the qualified bridge requires it. Idempotent. |
| `proscenium install` | On first non-frozen use, perform idempotent visible setup and create the project launcher; invoke native Ruby installation, generate dependency-only metadata, then conservative native JS install. May update native locks when manifests changed; never deliberately updates all dependencies. |
| `proscenium install --frozen` | Require native locks and any qualified bridge receipt/registration; fail if first-time setup is needed. Run native frozen Ruby/JS installation without committed file writes. |
| `proscenium sync` | Discover current locked gem manifests and generate dependency-only metadata. No JS installation or resolution. Fails if Ruby state is incomplete or provenance changes require a lock operation. |
| `proscenium lock` | Discover complete configured frontend universe, generate dependency descriptors, ask native managers to create/update lock metadata without JS install where supported; write provenance. Ruby source material may be downloaded. No frontend lifecycle execution. |
| `proscenium update ruby <gem...>` | Native targeted Bundler update, then bridge and native JS install. Reports Ruby plus induced JS lock changes. Empty target list requires `--all`. |
| `proscenium update js <package...>` | Native targeted JS update; Ruby lock remains byte-identical. Empty target list requires `--all`. |
| `proscenium add ruby ...` / `remove ruby ...` | Delegate to native supported manifest-editing commands; preserve native semantics; then synchronize both graphs. |
| `proscenium add js ...` / `remove js ...` | Native app/workspace dependency operation. Ordinary JS packages use native behavior; internal gem-context edges require qualified adapter mapping and do not expose gem assets. Cannot edit a published gem's manifest. |
| `proscenium inspect [gem] --json` | Report source, identity, dependency metadata projection, installed context, manifest digests, and bridge health. Read-only; redact credentials. |
| `proscenium doctor` | Check versions, manifests, lock consistency, linker support, source completeness, platform metadata, and resolver map. Report app imports of packages the app's own package.json does not declare but a gem context does: npm's hoisting makes them work, and they break under pnpm or Bun or when the gem drops the dependency. No repairs without an explicit repair command. |
| `proscenium gem check <path-or-gem>` | Validate source or built archive, packaged frontend contents, existing asset paths, and dependency declarations; do not execute author builds. |
| `proscenium migrate --plan` / `migrate` | Produce or apply adoption changes for existing gem asset projects and repository fixtures with rollback snapshots. Preserve unaffected constraints. |
| `proscenium clean --generated` | Remove only generated state owned by Proscenium. Keep native caches, locks, installed gems, and user files. |

Global options: `--project <path>`, `--json`, `--quiet`, `--verbose`. Installation options: `--frozen`, `--offline`, `--production`. Offline means no network on either ecosystem; adapters that cannot enforce it must fail instead of approximating it. `--production` omits app JS devDependencies using native semantics and honors existing Ruby group config; it never edits manifests to delete dependencies.

Use schema-versioned JSON events on stdout and human/native logs on stderr. Proposed event fields: `schema`, `event`, `phase`, `status`, `code`, `message`, `manager`, and optional sanitized `details`. Exit 0 success, 2 invalid input, 3 unsupported configuration, 4 frozen drift, 5 source/integrity failure, 6 native tool failure, 7 busy project, 8 interrupted or recovery needed. Report native exit status in details. Do not reinterpret an install failure as permission to change managers or regenerate locks.

Go invokes native tools through `os/exec` with argument arrays, explicit cwd, environment overlays, executable/version checks, streamed output, and per-host cancellation handling. Do not interpolate package names into a shell. Preserve native exit status and ensure interruption reaches child processes without orphaning the install phase. Separate native options as --ruby-arg and --js-arg; reject flags that undermine frozen/offline guarantees. Explicitly qualify the Ruby/Bundler environment so a bundle-exec parent does not impose stale activation on child operations. [Go subprocess API](https://pkg.go.dev/os/exec).

The Ruby adapter uses a small bundled helper to query Bundler's definitions, locked identities, installed roots, groups, and platforms as schema-versioned JSON. Batch the query across all gems; do not start Ruby once per gem or parse/evaluate Gemfile/gemspec syntax in Go. The helper never requires Proscenium's Rails entry point or compiler. Go reads and validates gem package.json manifests from the returned roots. Native Bundler still performs Ruby graph resolution and installation; native JS managers perform JS graph resolution.

## Installation and locking algorithm

1. Find the explicit project or enclosing configured workspace root. Validate manifest formats, manager/version/linker, owned paths, and source policy before mutation. Acquire a project lock with PID/start identity; stale-lock reclamation must be explicit and safe against PID reuse.

2. For frozen mode, validate required lock/provenance files and owned registration before invoking installers. Run Bundler with frozen configuration; for normal install use conservative `bundle install`, never `bundle update` implicitly. Capture failures without starting the JS phase.

3. Query authoritative Bundler metadata through the batched Ruby helper: definition/locked sources, installed roots, groups, source revisions, and platform variants. Transfer schema-versioned JSON to Go. Go discovers and validates dependency manifests from those sources without requiring gems, Rails, or the asset engine. Do not implement a Gemfile/gemspec evaluator in Go.

4. Resolve the configured frontend universe, including locked excluded groups. Use the installed source, a matching cached gem archive, or a pinned Git source. Never select a different Ruby version to obtain frontend metadata. Missing source in frozen offline mode is an error.

5. Validate the dependency-context name, dependency fields (rewriting references to other gems' contexts to the adapter's local-link syntax, per D1, only when backed by a gemspec runtime dependency), prohibited hooks, paths, platform constraints, and metadata projection. Gems without manifests skip this phase and retain ordinary asset behavior. Detect native workspace collisions before JS installation. Compute descriptor provenance, never a copied asset tree digest.

6. In non-frozen mode, stage changed dependency-only manifests and write them at stable final context paths before native installation. In frozen mode, regenerate them in memory and compare with the committed contexts; on any difference fail (exit 4) before writing a file or starting JS installation. Native lockfiles must reference final relative paths, not staging directories. Journal previous metadata for recovery; never replace unchanged contexts or their native dependency layout on a no-op install. Proscenium writes no frontend files.

7. Invoke native JS install in the actual project root. Respect native auth, registries, proxies, private packages, patches, overrides, and linking configuration. Frozen commands are `npm ci`, `pnpm install --frozen-lockfile`, and `bun install --frozen-lockfile`, qualified per version. Preserve tree-affecting flags used to create locks.

8. Check source/dependency manifest hashes again, native success, workspace enumeration, peer identity where required, and resolver health. Associate each installed gem root with its native dependency context; do not redirect asset roots. Write local map/state atomically and descriptor provenance in non-frozen operations. Frozen operations verify committed artifacts stayed unchanged.

9. Release the process lock and report each phase. Before a build, reject invalid or stale bridge state. A Ruby install may have succeeded while JS failed; report that explicitly and allow retry from completed phases without falsely claiming a cross-ecosystem atomic transaction.

No-op install MUST retain native locked choices, unchanged dependency-context metadata, and user manifest bytes. First registration, metadata-projection changes, additions/removals, and manager-format upgrades may cause necessary native lock churn. Changes solely to a gem's frontend code are handled by the existing asset engine and do not trigger dependency synchronization.

Frozen mode MUST fail for missing context registration, changed gem dependency manifests, incompatible locked source identities, changed native constraints, unqualified manager changes, or incomplete platform descriptors. It never rewrites the committed context metadata: it regenerates it in memory and fails (exit 4) if the result differs from what is committed. It may download locked dependencies when online. It does not hash or reconstruct every frontend file as bridge state. Native tools remain responsible for source/package integrity; lockfiles are written exclusively by their managers.

Do not temporarily register dependency contexts, generate a native lock against them, then remove their registration from package.json. That leaves native inputs inconsistent. Because context metadata is committed, a native frozen install (`npm ci` and equivalents) in CI sees the same inputs as `proscenium install --frozen`; there is no frontend tree materialization step.

[npm clean-install guarantees](https://docs.npmjs.com/cli/v12/commands/npm-ci/). [pnpm installation and frozen flags](https://pnpm.io/cli/install). [Bun native lockfiles](https://bun.sh/docs/pm/lockfile). [Bundler deployment behavior](https://bundler.io/guides/deploying.html).

## Asset resolver integration

Add a gem-to-dependency-context config map alongside `RubyGems`. Each participating entry contains the installed gem identity/root, candidate dependency-context path, native linker identity, and relevant manifest hashes. Preserve `RubyGems` and all existing asset source roots for every gem. Gems without manifests keep current app-level lookup. Do not infer context solely from a hoisted root node_modules/@rubygems link.

Relative imports, CSS references, source reads, and file ownership MUST continue to resolve from the original installed gem paths through the current engine. Only external package dependency lookup uses the participating gem's qualified native installation context. Package-internal imports and self references must retain current source-package semantics; do not blindly change every lookup's base directory. A missing dependency for a participating gem produces an actionable diagnostic. Gems without manifests retain existing app-context lookup and current explicit external/import-map behavior.

An external import from a participating gem's file MUST be resolved as if the importer lived in its context directory (`.proscenium/packages/<gem>/`), with no fallback to the app root. That is the only lookup base that gives the right answer on every adapter: npm hoists a gem-only dependency to the root `node_modules` and nests a conflicting version under the context, while pnpm and Bun 1.4 link a gem's dependencies under the context only and leave the root without them (see [Layout probes](#layout-probes-3-october-2026)). Falling back to the root would silently pick the app's version of a package the gem pinned differently, or, on npm, work only by accident of hoisting.

Symlinks: bundled builds follow them, but unbundled builds and resolve-only lookups set `PreserveSymlinks: true` (`internal/builder/build.go:105`, `internal/builder/compile.go:125`, `internal/resolver/resolve.go:147`). Under pnpm and Bun the app and a gem reach one shared package such as React through different link paths that end at the same file, so with symlinks preserved an unbundled page can load it twice under two identities. Dependency-context lookups MUST identify a package by its real path, or by a manager-aware canonical identity, so one real file is one module in every mode. C12 and C13 assert this through Proscenium's resolver in both bundled and unbundled mode, not only through Node's `require.resolve`.

Keep existing Proscenium gem import and entry-point behavior as the asset-resolution baseline, including its current esbuild conditions and legacy deep paths. A dependency-only workspace has no asset exports for ordinary Node resolution. The new feature must not impose a new native-package API on existing gem imports. Tests distinguish external JS package dependency lookup from source-local/self-reference and gem asset lookup.

Preserve `/node_modules/@rubygems/<gem>/...` URLs, manifest lookup keys, CSS module identity, __filename/__dirname virtual identity, fonts and images, dynamic import chunks, and bundled/unbundled behavior. Physical paths under .proscenium must not leak into browser imports or digest identity. External dependency files in native stores need manager-aware stable asset URL mappings; raw `.pnpm` or `.bun` physical storage paths are not a public API. The same file lives at `node_modules/<pkg>`, `.proscenium/packages/<gem>/node_modules/<pkg>`, `node_modules/.pnpm/<pkg>@<version>/node_modules/<pkg>` or `node_modules/.bun/<pkg>@<version>/node_modules/<pkg>` depending on the manager and on version conflicts. Bundled output is unaffected, because dependency code is inlined, but unbundled modules, code-split chunks and dependency assets (fonts, images, CSS `url()`) carry URLs. Stage C MUST define one URL scheme for a dependency file that does not depend on the manager or its hoisting decisions (for example package name, version and path within the package, plus a short digest of the resolved peer providers whenever they differ between installed copies), serve it through the existing middleware, and map it back to the real path, so a URL, a manifest key or a CSS module identity does not change when the manager or the lock does. Name and version alone do not identify an instance: one package version installed for two contexts with different peer providers is two module instances (pnpm keeps them as separate peer-suffixed store entries), and if both got the same URL an unbundled page would load one and resolve its peer import against the wrong provider.

Rails side-loading continues from installed gem view/component paths. Existing source-map locations, aliases, SVG handling, CSS URL resolution, frontend replacements, and manifest keys retain their original source identity. No gem-to-copy or reverse-copy mapping is needed. Native dependency-store paths still need the existing safe URL abstraction, with additional linker context only where required.

Invalidate dependency-context state and Go-facing lookup configuration coherently when gem identities, gem dependency manifests, the generated context metadata, or linker configuration change. Do not key it on the whole native lockfile: an ordinary `pnpm add left-pad` changes the lock without touching any gem's context, and must not force `bin/proscenium install`. Use one immutable mapping generation per request/build. Frontend-only path-gem edits keep the current development asset behavior and require no bridge sync or generated asset copies. Dependency-manifest edits require explicit install/sync or an opt-in metadata watcher. Avoid Go calls during Rails initialization because of the repository's documented Puma preload/fork hazards.

## Cross platform and deployment behavior

Separate platform-independent dependency metadata from host-specific native installations. Generated context paths are project-relative and case-safe; installed gem roots remain local runtime mappings supplied by Bundler. Serialize portable paths with slash form and convert only at filesystem boundaries, following the repository's two-path-space convention. Frontend source bytes and executable modes remain as installed by Bundler.

Windows must work without Proscenium-created source links or frontend copies. The native manager may require its own dependency links/junctions and must be qualified under ordinary-user conditions. Current CI enabling Git symlinks does not prove this. Test drive/UNC paths, spaces, reserved names, case collisions, long paths, and metadata replacement while processes run; Proscenium does not transform gem source line endings.

Inspect each declared Ruby platform's locked dependency manifest without loading its extension. V1 requires equivalent projected dependency metadata across variants; differing declarations are unsupported until a profile-aware native-lock design is proven. Frontend payloads may differ exactly as supplied by native gem variants and are served from the selected installed variant. No copied payload variants or frontend tree digests are recorded. Never commit installed absolute gem roots.

Native optional OS/CPU/libc packages are resolved and installed by the selected JS manager. Do not copy node_modules across OS/architecture/libc boundaries. Test a lock produced on macOS in Linux and Windows with each manager's supported platform policy; native lock formats can differ in how they represent optional packages. A platform graph difference that requires a lock rewrite must be fixed through native tooling before freezing, not silently patched by Proscenium.

Deployment sequence: provision pinned Ruby/JS tooling; restore compatible caches; run bin/proscenium install --frozen --production; precompile through existing Rails tasks where needed; run an asset smoke check; then start Rails. The launcher starts the project-selected Go CLI when its binary is installed. If Proscenium itself is absent, the minimal bootstrap first invokes native Bundler, then hands off to the packaged binary. Go coordinates the remaining Ruby/JS phases. Neither path requires a global CLI, user Go compiler, or Rails registry. Preserve frozen/offline restrictions throughout and use native production omission/build-stage semantics.

A Go CLI built without cgo may be qualified for musl separately, but the current Proscenium C-shared/FFI asset engine remains unsupported there. V1 gem distribution initially follows the existing qualified platform list; a pure-Go build alone does not prove Alpine packaging or Rails asset support. Supporting the engine on musl requires a separate loading-architecture investigation.

[Current platform build policy](https://github.com/joelmoss/proscenium/blob/b3c795745ceb6f4810d41283616dee61865834d9/AGENTS.md). [Bundler lockfile checksums and variant handling](https://bundler.io/blog/2024/12/19/bundler-v2-6.html).

## Security and failure recovery

Treat Gemfile/gemspec evaluation, native extension builds, JS dependency scripts, manager plugins/config, and native binaries as existing execution trust boundaries. Delegation does not sandbox those tools. Proscenium's added manifest parser, metadata writer, descriptor receipt reader, and process launcher must introduce no implicit execution path.

Preserve TLS, native authentication/checksum verification, lock checksums when available, private scopes, script approvals, and patch policies. Never refresh failed checksums automatically. Bind gem dependency metadata to locked source identity and original manifest bytes. Mutable path-gem dependency declarations require descriptor regeneration before frozen deployment; frontend-only edits do not alter the JS graph and remain subject to existing engine behavior and native source policy.

Apply containment and race checks when reading manifests, inspecting archive metadata, and writing owned bridge state. Guard against traversal, unsafe symlink targets, archive expansion abuse, case collisions, oversized metadata, and special files. Native Bundler installs gem payloads; Proscenium does not extract asset trees. Asset-serving authorization continues to use existing gem roots and file rules; generating dependency metadata grants no new serving permissions.

Never let gem metadata change application script approvals. Bun's trustedDependencies and pnpm's version-specific build approval policy must remain native application policy. Do not claim lifecycle equivalence among managers; test each baseline. `--ignore-scripts` does not mean arbitrary later task commands are blocked.

Logs and JSON exclude credentials, auth headers, tokenized source URLs, home-directory prefixes, and private manifest values unrelated to diagnosis. Committed config/provenance contain no secrets. `inspect` distinguishes checksums from signatures/provenance authenticity. Auditing delegates Ruby and JS ecosystems to their native compatible tools and reports their separate coverage.

The journal records snapshots/hashes of touched files, previous bridge roots, and phase status. On interruption, mark local state invalid before any subsequent asset build. Recovery verifies snapshots against current user edits, then resumes or restores owned bridge/config files. Do not overwrite concurrent edits. Native caches and installed Ruby gems can remain after failure; node_modules may need native reinstallation, especially after npm ci removes it. Successful retry regenerates a coherent map.

[Bun lifecycle and trust policy](https://bun.sh/docs/pm/lifecycle). [pnpm 10 build-script settings](https://github.com/pnpm/pnpm.io/blob/main/versioned_docs/version-10.x/settings.md).

## Performance strategy and measurable gates

Keep resolution delegated and reuse native package caches/stores. Proscenium may cache validated manifest descriptors keyed by locked source identity, source manifest hash, metadata projection version, and platform descriptor. Local installation state additionally includes manager version, linker/config digest, the generated context metadata, the Gemfile.lock entries of participating gems, and runtime/platform identity, but not the whole native lockfile or Ruby lock, so app-only native commands leave it valid. There is no frontend projection cache or extra copy of gem assets.

Leave unchanged dependency contexts in place so native links and node_modules survive. Rewrite only changed generated metadata, using safe atomic writes. The native manager alone manages dependency payloads and pruning. Source-only gem edits need no metadata regeneration. Lockfile-only operations must not load Rails or esbuild.

After the authoritative Bundler query, Go may parse and validate dependency manifests concurrently with bounded worker and I/O limits. Serialize project mutation and native JS installation; use project/cache locks and one coherent map generation. Batch Ruby metadata work instead of per-gem Ruby startup. Retain current asset watchers and never hash every gem tree on a browser request. Use native locked validation before skipping work; do not trade dependency correctness for a faster no-op path.

Proposed targets, not measured results: warm no-op orchestration overhead <=1 second at p95 for 100 participating gems; unchanged generated manifests have no writes; warm bridge overhead <=20% above the equivalent native baseline. Add startup benchmarks for direct Go execution, the RubyGems wrapper, the project launcher, and the batched Ruby metadata helper. Help/version and Go-only metadata commands should avoid Ruby child processes after binary launch; install phases retain native correctness checks. Record process count, manifest bytes, cache hits, native durations, orchestration CPU/wall time, and launcher overhead separately. Proscenium-written frontend bytes MUST equal zero. Calibrate startup/timing budgets on pinned hosts before release; using Go is a design choice, not proof of a measured speedup.

Benchmark cold checkout, warm cache with empty node_modules, no-op install, one changed path gem, one upgraded registry gem, failed network, and production omission. Use five measured repetitions after warm-up and report median/p95 with hardware, manager, runtime, lock hash, registry/cache state, and generated bytes. The local fixture timings are not product benchmarks.

## Adoption migration and rollback

The engine registry controller is unused, so it needs no compatibility obligation, deprecation period, or rollback path. The real migration population is the three known consumers: codaset moves off the hosted registry (its `@rubygems:registry` line in `.npmrc` and its `@rubygems/proscenium-ui` entry in package.json), and platform and london drop their `github:` pins for `@rubygems/hue`. Each is an acceptance case for `migrate`, not a fixture cleanup. The hosted registry is retired by the maintainer after codaset migrates. Adoption first enumerates existing gem asset imports, package manifests, bundled gem versions, and frontend installation assumptions. `migrate --plan` prints exact manifest/config changes and expected native lock updates before applying anything.

1. Snapshot manifests, native locks, owned configuration, and descriptor state. Verify existing gem asset imports and installed source roots as the baseline. Validate participating dependency manifests. No server is required and no frontend assets are copied.

2. Register qualified dependency-only contexts and generate their metadata. Replace obsolete fixture registry dependency declarations only with graph edges proven necessary for dependency installation or peers. Preserve gem asset imports; do not describe generated contexts as complete native packages.

3. Ask the selected native manager to regenerate necessary native lock entries. Review all unrelated graph churn against a baseline migration fixture; fail the automated migration if it changes unrelated declarations or invokes a full update.

4. Remove only obsolete Proscenium scoped registry entries after confirming no other dependency still needs them. Do not replace .npmrc, .yarnrc.yml, or other private registry credentials wholesale.

5. Run a fresh frozen installation with Rails stopped, existing gem asset regressions, and dependency-context import smoke tests. Assert that no gem frontend copies or installed-gem writes occurred. Update bootstrap/CI instructions, then remove reliance on tracked fixture node_modules.

Gems without package manifests keep existing asset serving and app-level dependency lookup before and after adoption. Self-contained files need no JS install. Missing app-provided external dependencies retain existing actionable behavior. Invalid present manifests, an invalid context name, required frontend build hooks, nested projects, and unsupported local file references receive concrete participation errors.

Replace the registry implementation in this feature: remove the controller, its engine routes, registry setup documentation/comments, and obsolete registry-specific dependency rationale. Convert strict JSON, unreadable manifest, package identity, and deterministic-content tests into bridge validation/provenance coverage. Retain the asset-serving RubyGems middleware: it is distinct from the registry. Review whether the json dependency bounds remain needed elsewhere before changing them. Publish the bridge as experimental until each adapter qualifies; no registry transition release is required.

Rollback restores snapshot manifests/config/native locks, removes only owned generated registration/state, reinstalls through the previous native workflow for ordinary JS dependencies, and clears asset resolver caches. Existing asset-only gem imports use the previous engine mapping; automatic gem frontend dependency installation is unavailable after rollback unless declared through the prior ordinary JS workflow. Registry-backed fixture locks are replaced during implementation, not restored as a supported application mode. No published gem content or shared caches are modified.

## Conformance test matrix

Every fixture compares a native baseline with an explicitly specified dependency-only consumer manifest against a Proscenium project using a real installed gem with equivalent dependency declarations. Compare per-manager graphs, diagnostics, scripts, locks, and dependency identity. Separately compare Proscenium asset behavior against the existing engine using the original installed gem files. Ordinary native importability of the gem is not the baseline. Frontend-only edits and no-manifest gems must preserve current behavior.

Run core rows for every qualified manager version on macOS ARM64/Intel, glibc Linux x86_64/ARM64, and Windows UCRT where supported. Pairwise coverage is acceptable for secondary flags, but release gates for clean/frozen install, imports, platform variants, no-registry behavior, and failure recovery run on every supported host/adapter combination. Unsupported combinations must fail before mutation.

| ID | Fixture | Required result |
|---|---|---|
| C01 | No manifests; self-contained gem and app-dependent gem | Existing in-place serving; no empty context or needless settings; self-contained assets work and external imports use app dependencies. |
| C02 | Built gem ships JS + CSS + manifest + registry dependency | Fresh install with Rails stopped; frontend reads remain at installed gem paths; native dependencies resolve; zero Proscenium asset copies. |
| C03 | External, vendored, path, registry and Git gems | Same stable virtual URLs; exact locked source identity; no installed gem writes. |
| C04 | Gem imports through Proscenium and native dependency-context lookup | Existing gem asset imports work; explicit context avoids accidental hoisting; metadata contexts are not advertised as native gem packages. |
| C05 | Existing user monorepo, exclusions and duplicate package name | Existing packages unchanged; collision errors before native writes. |
| C06 | pnpm 10, 11 and 12 with pnpm-workspace.yaml absent, present and stale | Correct workspace enumeration; YAML remains authoritative; no accidental policy overwrite. |
| C07 | Existing package-lock, shrinkwrap, pnpm lock, bun.lock/bun.lockb; yarn.lock | Manager selection and lock precedence correct; no implicit format conversion; yarn.lock gives the unsupported-manager error. |
| C08 | Repeated frozen install on unchanged inputs | Success; committed manifests, native locks and provenance byte-identical. |
| C09 | Stale/missing descriptor receipt or changed dependency manifest | Frozen fails before JS resolution; no lock repair or registry fallback. |
| C10 | Version ranges, prereleases, dist-tags, aliases, Git URLs, tarballs | Native per-manager baseline semantics; Ruby and JS versions independent. |
| C11 | Conflicting transitive versions across two gems | Distinct native contexts retained; no dependency flattening. |
| C12 | Present/missing/incompatible React peer, optional peer metadata, asserted through Proscenium's resolver bundled and unbundled | Same native peer policy; app and gem React identity asserted when sharing is intended. |
| C13 | Two consumers with different peer providers | Compare workspace peer placement against baseline; fail qualification if desired consumer identity cannot be represented. |
| C14 | Optional dependency fails build/fetch or is omitted | Native optional behavior; nonoptional failures remain failures. |
| C15 | OS/CPU/libc packages; cross-host lock created elsewhere | Native compatible variants installed; frozen inputs unchanged; incompatible engine host diagnosed. |
| C16 | engines, engineStrict, overrides/resolutions, patches/catalogs | Root policy preserved; gem cannot promote its own policy. |
| C17 | Gem devDependencies and app devDependencies | Gem consumer dev tools absent; app development and production omission match baseline projection. |
| C18 | Install hooks, prepare hooks, binding.gyp in gem | Author-contract error before execution; native dependency scripts follow native policy. |
| C19 | npm/pnpm build approvals, Bun trustedDependencies, ignore-scripts | Compare native behavior and executed markers; no auto-approval from gem metadata. |
| C20 | exports/imports, type, ESM/CJS, module/browser/main, sideEffects | Existing gem/self-reference behavior preserved; external dependency conditions correct; no exports point to absent context assets. |
| C21 | CSS @import/url, CSS modules, fonts, SVG, TS types | Original gem files resolve in place; stable class identity and URL ownership; no frontend files under .proscenium. |
| C22 | Bundled/unbundled code, dynamic chunks, aliases and import maps | Existing Proscenium outputs preserved; intended missing/external behavior explicit. |
| C23 | Source maps, metafiles, manifest precompile, Rails side-loading | Original installed-gem source identity and existing virtual mapping preserved; no copy/reverse-copy paths. |
| C24 | Bun runtime harness plus new installer graph | App/gem imports and CSS module identity correct; harness-specific chunk caveats retained. |
| C25 | Yarn project in any mode (packageManager field, yarn.lock, .yarnrc.yml) | Unsupported-manager error (exit 3) before any write; no config or lock change. |
| C26 | Contained/escaped file refs, cross-gem range and workspace refs | Unsupported relative file/link declarations fail clearly; any qualified variant proves portable native context without frontend copying. |
| C27 | Unicode/spaces/case collisions/UNC/drive/reserved names/long paths | Valid paths work; unsafe/colliding paths fail deterministically. |
| C28 | Read-only shared gem install and ordinary-user Windows | Dependency metadata generates without gem writes, source mirrors, or privileged Proscenium links. |
| C29 | Manifest/archive-metadata traversal, symlink races and special files | Safe metadata reads/writes; no writes outside owned state; existing asset security tests retained. |
| C30 | Tampered native package/gem archive, manifest or descriptor cache | Native integrity verification retained; descriptor mismatches fail; no claim that bridge receipt authenticates every asset byte. |
| C31 | Private registries, proxies and credential-bearing URLs | Native auth works; no credentials in logs/provenance; no Proscenium registry requests. |
| C32 | Excluded Ruby groups; unavailable locked sources | Fixed descriptor universe; offline cache miss explicit; no production-only graph drift. |
| C33 | Different Ruby platform variants with differing frontend manifests | V1 rejects dependency differences; equivalent metadata passes; assets stay in the native selected gem variant. |
| C34 | Ctrl-C/power interruption at each journal phase | State marked invalid; safe resume/restore; asset builds never consume partial bridge. |
| C35 | Concurrent install, native command, editor changes | Project lock behavior correct; current user edits never overwritten during recovery. |
| C36 | Changed path gem, branch switch, upgrade/removal, rollback | Asset-only edits need no bridge sync; manifest changes invalidate context; Ruby source changes and native pruning handled correctly. |
| C37 | Packaged Go CLI; Ruby wrapper; Gemfile-first and fresh/missing/changed bundle | Correct OS/arch/version binary, no user Go compiler or downloads, one everyday install command, no Rails/engine loading; defaults need no settings/init; plain gem contains no stray binary; frozen drift fails. |
| C38 | Native JS targeted update; Ruby update changes Go CLI version | JS-only leaves Ruby lock unchanged; Ruby-induced JS changes reported; selected binary/helper protocol handoff works across Unix/Windows without loops or lost signals. |
| C39 | Existing gem asset app adopts bridge and rolls back; obsolete registry removed | Unaffected declarations unchanged; ordinary JS/legacy asset behavior recoverable; registry endpoint and shim documentation absent. |
| C40 | Direct Go startup, wrappers, batched helper, warm/cold install, one gem change | Process counts and overhead measured separately; no per-gem Ruby startup; calibrated native-baseline targets; zero frontend-copy bytes; no invented speed claims. |
| C41 | Real consumers: codaset (Bun, proscenium-ui), platform and london (pnpm, hue) | Fresh checkout installs with no hosted registry and no `github:` pin for a gem; each gem pinned only in Gemfile.lock; existing app imports and side-loaded assets unchanged. |
| C42 | Gem whose package.json lacks `version`, has a Ruby-style prerelease, or differs from the gem version (hue, proscenium-ui) | Context generated without `version` and linked via the adapter's local-link syntax on every supported manager line; no participation error; no registry request. |
| C43 | Gem declaring `react`/`react-dom` as `dependencies` instead of peers (hue) | Native result recorded per manager; one React instance in the app, or an author-contract diagnostic naming the fix. |
| C44 | Gem manifest declaring another gem's context by semver range, as a dependency and as a peer (`"@rubygems/other": "^1.0"`), with and without `other` as a gemspec runtime dependency, and with `other` absent from the bundle | With the gemspec dependency: rewritten to the adapter's local-link syntax (`workspace:*` for pnpm and Bun, `*` for npm), and a Gemfile.lock version outside the gemspec constraint fails in Bundler before any JS step. Without it, or with `other` absent: participation error naming both gems, nothing rewritten. As an optional peer: linked when `other` is in the bundle, omitted from the projection when it is not, never an error. The native install never requests `@rubygems/*` from a registry. |
| C45 | Native commands used directly: plain and frozen `npm`/`pnpm`/`bun install` on a fresh checkout, `pnpm add <pkg>` in a set-up project, and a Gemfile change followed only by a native install | Fresh checkout installs every gem's dependencies with no lockfile change; an app-only native command leaves Proscenium's state valid; a Gemfile change without `bin/proscenium install` fails `proscenium install --frozen` (exit 4) and the asset engine reports which gem is stale. |
| C46 | Same app installed by npm, pnpm and Bun in turn, with a dependency version conflict between app and gem and a gem-only dependency | Gem imports resolve the gem's version and the app's imports the app's on every manager; unbundled URLs, manifest keys and CSS module identities are identical across the three; no `.pnpm`/`.bun` segment appears in any URL. Includes C13's case: one package version consumed by two contexts with different peer providers gets two distinct URLs, each resolving its peer import to its own provider. |
| C47 | App code importing a package only a gem declares | Works under npm through hoisting, fails under pnpm and Bun; `proscenium doctor` reports it on all three. |

Test layers: Go unit tests for metadata validation/projection, containment, manager selection, descriptor receipts, cache keys, and journals; Ruby helper protocol tests against native Bundler; real-manager graph/lock/script fixtures; platform-gem artifact tests for the executable, Ruby wrapper, and existing engine library; Ruby/Go asset regressions and Rails/Bun end-to-end imports from original gem sources. Assert zero frontend copying or installed-gem writes. Test source-only edits separately from dependency changes, no-manifest gems, wrapper/helper process counts, and missing/incorrect binary errors.

## Implementation sequence and release gates

Stage A: prove dependency-only contexts with real installed gems before choosing a native representation. Compare metadata-only workspace, read-only direct-source registration, and metadata-only local descriptor alternatives. Gate on C01-C04, C08, C12, C13, C17, C20, C26, C28, C33, C42, C43, C44, C45 and C46. Require original source paths, zero asset copies, correct external imports, and shared React identity. A failing adapter is unqualified; copied frontend trees are not a fallback. The execution contract is below.

Stage B: implement the Go CLI and batched Ruby/Bundler adapter; package prebuilt binaries in the existing Proscenium platform gems behind a tiny RubyGems launcher. Implement Gemfile-first onboarding, idempotent setup, project launcher/bootstrap, descriptor metadata, optional settings, native commands, and frozen drift detection. Gate on correct platform/version artifacts, fresh/missing/changed bundle, selected-binary handoff, read-only gem roots, no Rails/FFI/engine loading by CLI commands, and measured startup overhead. No frontend copying, Go toolchain requirement for users, or separate CLI installation.

Stage C: connect gem identities to native dependency contexts at the existing Ruby/Go lookup boundary, with context-only lookup (no root fallback), real-path package identity in every build mode, and the manager-independent dependency URL scheme. Preserve existing source roots, relative imports, serving middleware, URLs, source maps, manifest/side-load behavior, and Bun harness semantics. No copied-source mapping and no runtime installation. Gate on relevant existing asset suites plus C20-C24 and source-only edit regressions.

Stage D: transactional journals, CLI update/add/remove/doctor, native adapters, migration, ordinary-user Windows and Linux qualification, performance calibration. Release each adapter only after its full mandatory matrix passes. An unqualified adapter remains an explicit error even if others ship.

Stage E: replace registry-backed repository fixtures with clean bridge installations, remove the unused registry feature and setup instructions, migrate codaset, platform and london (C41), publish adoption instructions, the gem author guide and compatibility evidence, and introduce stable bridge support for qualified adapters. The maintainer retires `registry.proscenium.rocks` after codaset is migrated.

### Stage A execution contract

Implement a disposable proof under `test/package_manager/stage_a/` and publish commands, tool versions, fixture manifests, normalized graph captures, lock hashes, and per-manager verdicts in `docs/plans/154-package-manager-stage-a.md`. The prototype may generate workspace metadata and use a test-only resolver seam to route **external dependencies** from an original installed-gem issuer to its candidate context. It must exercise existing source reads, relative/CSS resolution, and @rubygems URLs. This is a proof for Stage C, not a production CLI or resolver implementation. No prototype may copy assets or write installed gem roots.

Fixtures, all genuinely Bundler-installed into a temporary BUNDLE_PATH and then made read-only:

- Synthetic `.gem` archives built locally: the existing gem_npm fixture (string-length ^6.0.0), a self-contained stage_a_assets gem without package.json, and stage_a_widget_a/b at 1.0.0, which declare React ^18.3.1 peers and is-number 6.0.0 / 7.0.0 respectively; the app supplies React and react-dom 18.3.1. Manifests and frontend files are listed explicitly in each fixture's `spec.files`. Add incompatible/optional peer and separate-provider variants as baseline comparisons.
- proscenium-ui, a real public Git-source gem at a pinned revision (manifest version behind the gem version, `github:` dependency). It is committed or fetched like any other fixture and runs in CI.
- `stage_a_hue_shape`, a public synthetic gem that reproduces hue's awkward traits exactly: no manifest `version`, `react` and `react-dom` as plain `dependencies`, a `github:` dependency, and package.json missing from `spec.files` (installed as a Git source so the manifest is still on disk). This is the CI fixture for C42 and C43.
- hue itself, run **locally only**. `harleytherapy/hue` is a private repository, so its source cannot be committed here and public CI cannot fetch it. The maintainer runs the hue leg against a local checkout at a pinned revision, and `docs/plans/154-package-manager-stage-a.md` records only the revision, tool versions, commands and verdicts, never hue's source or manifest contents. The synthetic gem must reproduce every behaviour the hue run shows; if they diverge, fix the synthetic gem.

Order: pnpm with `stage_a_hue_shape`, confirmed locally against hue (the drift that has already happened), then Bun with proscenium-ui (codaset's case), then npm with the synthetic fixtures. npm has no real consumer here, so its evidence comes from synthetic gems only; say so in its verdict.

Initial proof matrix: macOS ARM64, Node 22.22.2 (the oldest Node npm 12 accepts) and Node 26, Ruby 3.4.8, Go 1.25.7 with GOWORK=off, and Bundler selected by the repository Ruby lock. Test the newest patch of every supported line (npm 10.9.x, 11.x, 12.x; pnpm 10.x, 11.x, 12.x; Bun 1.4.x) plus the floor of each manager's oldest supported line. Record every runtime version. Repository pins and newer candidates in the compatibility table, Intel macOS, glibc Linux and Windows remain unqualified until their Stage D/release runs. Stage A uses applicable architectural assertions from its listed C rows; production CLI diagnostics/transactions and ordinary-user Windows gates remain later tests, not fictitious Stage A passes.

For each representation, compare to a native consumer graph with identical projected declarations, root policy and seeded choices. Pass means identical normalized package identities/versions, dependency edges, peer providers, optional omission, script markers and success/error classes. Do not require equal physical trees or identical diagnostic prose. Repeated frozen runs must preserve each project's committed bytes. Bundle a joint app/gem probe through the resolver seam and execute it: shared React exports must compare ===, with one intended React module instance in that output. Compare missing/incompatible peers and distinct-provider cases against the native baseline rather than forcing every case to share.

Prefer the stable dependency-only workspace representation when multiple candidates satisfy every invariant. Per-manager alternatives are allowed only as explicit, tested capabilities with portable native locks and identical source-serving boundaries; never switch representation silently. Retain a descriptor receipt only if native committed inputs cannot detect a changed locked gem source/revision, original manifest hash, projection version/options or context registration. Demonstrate those one-at-a-time drift cases without committed host paths.

A candidate GO requires original source identity, distinct dependency contexts, correct peers, reproducible/frozen locks and no asset copies or gem writes. Zero qualifying adapters is an epic NO-GO: report evidence and reopen design without starting Stage B. A partial GO permits Stage B for those adapters only after maintainer sign-off recorded on issue #154; the others remain unsupported. v1 support for all three managers requires three independent GO results and subsequent release qualification.

Track stages as milestones on issue #154; split implementation child issues after Stage A settles the representation.

### Suggested repository changes

| Path | Proposed work |
|---|---|
| `cmd/proscenium/`, `internal/package_manager/` | Go CLI entry point and orchestration, metadata, native adapters, cache, journals and diagnostics; avoid importing the C-shared engine. |
| `exe/proscenium`, gemspec executable declarations | Tiny RubyGems launcher for the packaged Go binary; project launcher template and selected-version handoff tests. |
| Ruby/Bundler metadata helper under lib/proscenium | Small schema-versioned Bundler query helper and engine-side context reader; package-manager core stays in Go. |
| `Rakefile`, gemspec and release workflow | Build/package the Go executable separately from C-shared engine; qualify all platform artifacts; gate/clean CLI bytes in the plain gem. |
| `lib/proscenium/bundled_gems.rb`, resolver and builder | Separate source roots from bridge contexts; coherent map generation and invalidation. |
| `internal/types/types.go`, plugin/bundler.go, plugin/bundless.go, resolver/resolve.go | Gem dependency-context config and external package lookup; preserve original source resolution and stable asset URLs. |
| `internal/utils/utils.go`, manifest/source-path handling | Keep current installed-gem physical-to-virtual mapping and path security; qualify any native dependency-store additions. |
| `lib/proscenium/runtime/`, test preload generator | Consume mapped package contexts without changing runner-specific semantics. |
| `test/package_manager/`, new built-gem and manager fixtures | C01-C47 cases and executable comparison harness. |
| `.github/workflows/main.yml`, fixture manifests/locks | Clean bridge install; pinned manager matrix; eliminate registry boot dependency. |
| registry controller/routes/tests | Remove unused controller/routes; convert valuable parsing/integrity cases into bridge tests in this change. |
| README and migration guides | Gemfile-first onboarding, single everyday install command, gem author contract, CI, native command coexistence, platform caveats and rollback. |

Indicative human engineering planning estimate: 1-2 engineer-weeks feasibility; 2-3 orchestration/provenance; 2-3 resolver integration; 3-5 adapters/conformance/cross-platform; 1-2 migration/docs/performance. Total 9-15 engineer-weeks before external feedback, assuming the workspace peer gates pass. This is a planning assumption, not a benchmark or delivery commitment. The estimate predates dropping Yarn from v1, which removes one of four adapters from the adapter/conformance work; re-estimate after Stage A rather than adjusting these numbers by guesswork. If Yarn or multiple packages per gem become required, estimate them separately after prototypes.

Final acceptance: the Go CLI is packaged in each qualified Proscenium platform gem and works through the tiny Ruby launcher/project launcher without loading Rails or the engine; fresh registry-free dependency installation uses native locks; no user Go compiler, separate CLI install, or implicit binary download is required; platform artifacts and version handoff are verified; gem assets remain at installed roots with zero copies/writes; no-manifest behavior and native dependency/peer semantics remain correct; routine/frozen installs preserve user manifests; failures, recovery, exact compatibility, and measured startup/install performance are qualified; codaset, platform and london install without the hosted registry or `github:` gem pins (C41). v1 support for npm, pnpm and Bun requires all three adapters to pass; Yarn projects get the unsupported-manager error.

### Acceptance criteria

- [ ] Stage A records reproducible real-gem evidence (synthetic gems including `stage_a_hue_shape`, proscenium-ui in CI, hue locally) and GO/NO-GO results per representation and manager, including peer placement and app/gem React identity.
- [x] Decision D1 (context version source) is settled: omit `version`, reference contexts with `workspace:*` (pnpm, Bun) or `*` (npm).
- [ ] Packaged Go binaries, RubyGems/project launchers, and the batched Bundler helper pass platform/version, missing-bundle, handoff, cancellation, and frozen/offline tests.
- [ ] Gem assets remain at Bundler-installed roots with zero Proscenium frontend copies, mirrors, installed-gem writes, or privileged source links.
- [ ] Gems with package.json install native dependencies; gems without it keep existing serving and app-context dependency lookup.
- [ ] Existing @rubygems imports, public URLs, CSS identities, source maps, side-loading, precompile behavior, and Bun harness semantics pass regressions.
- [ ] Routine installs preserve user manifests; repeated frozen installs leave committed manifests, native locks, and required provenance byte-identical.
- [ ] Clean CI installs with Rails stopped and no scoped registry shim; unused registry code and instructions are removed.
- [ ] codaset, platform and london are migrated (C41) and `registry.proscenium.rocks` can be retired.
- [ ] `proscenium gem check` and the gem author guide ship, and `gem check` catches a manifest missing from `spec.files`.
- [ ] Every released adapter (npm, pnpm, Bun) passes its mandatory C01-C47 matrix on supported hosts; exact versions, unsupported modes (Yarn), and measured performance are documented.

### Related

- #82: existing registry refinement request; this plan replaces that feature.
- #137: registry findings; preserve useful validation/identity/integrity coverage when removing the controller. Decide closure when the replacement lands.

## Research limits and remaining decisions

Official manager, RubyGems/Bundler, Node, and esbuild documentation was checked on the research date. Version-sensitive facts are qualified against repository pins. Earlier local probes used complete local workspace packages, not dependency-only descriptors, real installed-gem lookup, or registry packages. No revised bridge implementation, production engine build, integration suite, Windows/Linux execution, PnP prototype, or real peer-context migration was completed. The asset-serving requirement is settled; the native dependency representation remains a hypothesis. No Go CLI executable or revised platform gem was built or benchmarked during this specification work; binary packaging, helper protocol, and startup budgets remain implementation gates.

Highest-risk open questions: native peer/root attachment for dependency-only contexts, directing the existing engine's external dependency lookup without changing source-local semantics, portable local file dependencies, and cross-platform descriptor collection. Stage A must prove these against real gems and existing engine behavior. If a representation fails, investigate another metadata-only/native mechanism or leave that adapter unqualified. Do not recover by copying frontend assets, flattening dependency declarations, inventing a registry, or replacing native resolvers.

Open decisions, each settled by the maintainer and recorded here:

- None open. Decisions settled so far are below.

Settled on 3 October 2026:

- **D1: a dependency context's version.** The generated context omits `version`, and every reference Proscenium generates to it uses the adapter's local-link syntax: `workspace:*` for pnpm and Bun, `*` for npm (npm rejects `workspace:` inside a workspace package on 10.9.9, 11.6.2 and 12.2.0). A gem author's range for another gem's context is rewritten the same way, but only when the other gem is a runtime dependency in the referencing gem's gemspec, so Bundler both guarantees the context exists and checks the version; any other reference is a participation error (see [Gem author contract](#gem-author-contract-and-dependency-metadata)). Bundler has already selected the gem version, so a JS-side version adds nothing and would be a second pin that can drift. Rejected: (a) requiring authors to maintain `version` (rejects hue today, adds a drifting pin); (b) copying the Gemfile.lock version (Ruby prerelease syntax breaks pnpm 10/11, and conversion is extra code with no consumer). Evidence: [Version probes](#version-probes-3-october-2026).
- **Context metadata is committed**, not ignored, so native commands are safe to use directly; see [Fresh-checkout probes](#fresh-checkout-probes-3-october-2026).
- **Support rule:** owner-maintained release lines only; see [Scope and compatibility policy](#scope-and-compatibility-policy).
- v1 supports npm, pnpm and Bun; Yarn is out. The hosted registry is retired at the maintainer's discretion after codaset migrates, so there is no deadline driving a stopgap.
