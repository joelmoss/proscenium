<!-- /autoplan restore point: "/Users/joelmoss/.gstack/projects/joelmoss-proscenium/docs-154-plan-review-autoplan-restore-20261003-233014.md" -->
## Implementation plan
# Proscenium next generation package manager engineering specification

Research date: 3 October 2026. Repository baseline: `joelmoss/proscenium` at `b3c795745ceb6f4810d41283616dee61865834d9` on `master`.

Status: reviewed design specification. The asset-serving boundary is confirmed; the dependency-bridge representation stays unproven until the Stage A pilot passes. Proscenium MUST serve frontend files from the installed Ruby gem using its existing functionality. None of this is implemented yet. MUST, SHOULD and MAY describe requirements. Repository observations, documentation findings, local measurements and decisions are identified separately.

Tracking issue: [#154](https://github.com/joelmoss/proscenium/issues/154). This document is the only copy of the plan. The issue tracks stage status and records maintainer sign-off; it does not restate the plan.

Revised 4 October 2026 after a full plan review: v1 is a pilot on pnpm and Bun, npm and Yarn are unsupported, gems opt in to participation, the CLI is Ruby and runs inside the app's bundle, and v1 has four commands. [Research limits and settled decisions](#research-limits-and-settled-decisions) lists every settled decision; the reasoning behind each is in the Review record at the end of this file. `bin/check-154-plan` keeps this body free of superseded text and gates the start of Stage A.

## Motivation

**Gem-first installation.** Adding a gem that opts in should make its JS dependencies installable with one command, `bundle exec proscenium install`. Authors keep declarations with their code; apps need not duplicate each gem's dependency list or publish its assets to a registry. Gems that do not opt in keep existing serving and app-provided dependencies.

**One version pin, not two.** Today an app that uses a gem's JS pins the gem twice: once in Gemfile.lock and again in package.json (a `github:` URL or a registry version). The two pins have drifted in practice (hue, below). The bridge makes Gemfile.lock the only pin for the gem; package.json pins only ordinary JS packages.

**Native compatibility.** The original workspace proposal aimed to avoid emulating Bundler and the JS resolvers. Preserve native manifests, locks and dependency/peer/optional/platform/script behavior. Separate gem contexts prevent dependency flattening; native root-lock integration avoids a second shadow graph.

**Existing asset serving.** Proscenium already serves installed-gem files. Only dependency installation and lookup need extending. Copying would add another source location and synchronization state. Preserve `@rubygems` imports, relative paths and asset URLs; generated contexts contain metadata only.

**Registry-free installs.** Installs must work with Rails stopped, without scoped-registry setup or a hosted registry service. This removes the current fixture's running-app installation dependency while retaining the distinct RubyGems serving middleware.

**One command, no extra tooling.** The CLI is Ruby. It ships in the existing gem as `exe/proscenium` and runs under `bundle exec`, where Bundler is already loaded, so there is no separate CLI to install, nothing to compile and nothing to download. Its speed is measured against the bare native install ([Performance](#performance-strategy-and-measurable-gates)).

**Evidence before commitment.** The Stage A pilot must prove original-source lookup, portable locks, native peer policy and shared React identity on pnpm and Bun before any CLI or engine work starts. A failed adapter stays unsupported; copied assets, registry shims and silent graph changes are excluded fallbacks.

### Why not publish gems' JavaScript to a registry

Publishing each gem's JavaScript as its own registry package was considered and rejected. Private gems such as hue cannot be published publicly. A second release channel drifts from the gem version, which is the double-pin problem again. And a gem's JavaScript must match the Ruby code in the same gem release, which only the gem itself guarantees.

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
- **Manifest versions are unreliable.** hue's current package.json has no `version` at all; older installed checkouts say `0.2.3` while the gem is `0.5.3`. proscenium-ui's package.json says `0.2.0` while `Proscenium::UI::VERSION` is `0.2.1`, and codaset's lock resolves `0.2.1`, so the hosted registry already ignores the manifest version. A rule that a missing or invalid manifest version is a participation error would have rejected hue outright. Decision D1 ([settled decisions](#research-limits-and-settled-decisions)) removes the dependency on the manifest version.
- **hue declares `react` and `react-dom` as `dependencies`, not `peerDependencies`.** In a separate dependency context that can give hue its own React copy, a second React instance next to the app's. This is the C12/C13 risk in a real gem rather than a synthetic one. Stage A must show what each manager does with it; the likely outcome is an author-contract diagnostic ("declare React as a peer"), not bridge magic.
- **Both gems use `github:` dependencies** (`sourdough-toast`). Git URL dependencies inside a gem manifest are a v1 case (C10), not an edge case.
- **Neither gem opts in yet.** Participation is opt-in ([Opting in](#opting-in)), so the pilot adds the gemspec metadata line to hue and proscenium-ui, or london, platform and codaset opt them in from `proscenium.json`.

## Decision and product contract

Implement the package-manager CLI in Ruby, as the gem's `exe/proscenium` executable. It runs under `bundle exec` inside the app's own bundle, reads Bundler's already-loaded definition in process, and starts pnpm or Bun as a child process. Native Bundler continues to own Ruby resolution and installation, including gem frontend files; the developer runs `bundle install` as usual and the CLI never runs Bundler itself. pnpm or Bun owns JS dependency resolution, installation, lifecycle policy and native locks. npm and Yarn are unsupported in v1. The CLI associates each participating gem with a native JS dependency context; it does not reimplement either ecosystem's solver.

A gem participates only when it opts in: its author sets gemspec metadata, or the app opts it in from `proscenium.json` ([Opting in](#opting-in)). Every other gem keeps today's asset serving and app-context dependency lookup, whether or not it ships a package.json.

Frontend assets MUST remain in the directory where Bundler installed the gem. Proscenium MUST rely on its current gem asset-serving functionality; it MUST NOT copy, relocate, extract or mirror frontend asset trees to make this feature work. The bridge uses project-local, dependency-only workspace manifests. These are generated installation metadata, not copies of the gem's frontend package. This representation requires feasibility testing on pnpm and Bun. The feature replaces both the unused engine registry controller and the hosted registry codaset uses today, and requires no Rails registry server, hosted registry, special scoped registry setup or publication of gem assets.

Preserving `Gemfile`, gemspec and `package.json` means preserving native formats, authority and editing workflow. Routine installs MUST leave user manifests unchanged. The first non-frozen install performs one-time, idempotent registration (the workspace entry and three `.gitignore` lines) and prints those owned edits as a unified diff before writing them; later installs do not repeat them. Preserve all unrelated declarations, scripts, overrides, workspace patterns and lock semantics. Existing Proscenium gem imports remain the asset API; dependency contexts do not expose ordinary native gem packages.

This qualification is essential: a fully transparent workspace that makes no root workspace configuration changes is not established by the research. If “preserve” instead means that every root manifest must remain byte-for-byte unchanged even at initialization, the integrated workspace design does not satisfy that stronger constraint. Do not hide temporary manifest edits, silently run a second graph, or label such an arrangement native root-lockfile compatibility.

The user-facing workflow is Gemfile-first: add the gem and Proscenium to the Gemfile, run `bundle install`, then run `bundle exec proscenium install`. The same command runs again after every Gemfile change. Defaults use existing native manager signals and need no hand-written settings. Native pnpm and Bun commands remain supported. Rails boot and asset requests never install dependencies or contact registries.

Primary users are Rails developers consuming gems with frontend dependencies, gem authors shipping frontend components, and deployment systems installing the same application on different hosts. Success means a fresh checkout installs JavaScript dependencies and serves the gem's JS/CSS directly from its installed location without a running Rails server or registry shim, using committed native lockfiles. Concretely: codaset, platform and london each install from a fresh checkout with no hosted registry and no `github:` pin for a gem, and each gem's version is pinned only in Gemfile.lock (C41).

## Verified repository architecture

The current repository is a Rails frontend engine and compiler, rather than an independent package resolver. The Ruby layer integrates with Rails, Rack, ActionView, asset manifests and helpers. A Go shared library uses an esbuild fork and is called through FFI. The package-manager feature extends this architecture without replacing its asset engine.

| Existing component | Observed behavior | Consequence for this specification |
|---|---|---|
| `lib/proscenium/bundled_gems.rb:7` | Uses `Bundler.load.specs`, sorted by gem name; maps gems to installed roots. Proscenium itself maps to `lib/proscenium`. `Bundler.load.specs` omits gems in `BUNDLE_WITHOUT` groups ([Review probes](#review-probes-4-october-2026)). | The one Ruby reader of Bundler for both the engine and the CLI, so the two never disagree about which gems exist. Bridge discovery needs the actual gem root, not the special asset root; orphan checks need `Bundler.locked_gems`. |
| `lib/proscenium/builder.rb:218`, `lib/proscenium/runtime/server.rb:235`, `main.go`, `internal/types/types.go` | Both Ruby config sites pass the `RubyGems` root mapping and build configuration to Go through FFI. | Add the dependency-context map beside `RubyGems` in both sites. Go ignores unknown config keys, so a Go-side test asserts the new key arrives. |
| `internal/plugin/bundler.go:311-337` | A gem's bare import resolves using the installed `node_modules/@rubygems/<gem>` real path when present; otherwise falls back to the app root. | Replaced, for participating gems only, by the one context lookup. |
| `internal/plugin/bundless.go:46`, `:80`, `:345-349`, `:384-417` | Unbundled builds: the CSS-module and SVG resolve (46); real-path normalization, only when the resolve dir is inside `node_modules` (80); a bare-with-extension shortcut that emits `/node_modules/<specifier>` without resolving (345); a three-step chain of resolve dir, gem-root retry and app-root retry (384). | All routed through the one context lookup for participating gems. |
| `internal/css/mixins.go:60` | CSS mixin lookup goes through `resolver.Resolve`. | Same lookup. |
| `internal/resolver/resolve.go:147` | Resolve-only builds preserve symlinks, use environment plus `proscenium` conditions, and prioritize `module`, `browser`, then `main`. | Installation parity and browser module-resolution parity are different contracts. Preserve the current browser conditions. |
| `lib/proscenium/resolver.rb`, `internal/utils/utils.go:379` (`UrlPathFromFsPath`) | Maintains real filesystem and virtual URL paths, including `@rubygems` gem addressing. | Keep installed gem roots and the existing virtual URL mapping; dependency URLs stay real-path in v1. |
| `lib/proscenium.rb:18` | `ALLOWED_DIRECTORIES = 'app,lib,config,node_modules'` limits what the middleware serves. | Extended to nested copies under `.proscenium/packages/<gem>/node_modules/`. |
| `lib/proscenium/railtie.rb`, middleware, side-loading and importer | Configures on-demand bundling, side-loading, helpers, manifest loading and precompilation tasks. | No Rails boot requirement for installation. Preserve bundled and unbundled asset behavior. |
| `lib/proscenium/runtime/` | Bun testing uses a Rails daemon, middleware and a Bun plugin; the daemon disables code splitting for the harness and caches builds (`runtime/server.rb:502`). | Bun as an installer and Bun as a test runner are separate integrations; test both. The daemon's cache must respect the install marker and the mapping generation. |
| `app/controllers/proscenium/registry_controller.rb:94` | Serves a packument for the installed gem version only; advertises `dependencies`. | It is a registry compatibility path, not a general resolver. Peers and optional dependencies are not included in that packument. |
| Registry controller at lines 163 and 191 | Deterministic tarball contains only `package/package.json`; uses the gem's manifest bytes, or synthesizes a minimal manifest. | Existing package contents do not themselves expose the gem's JS/CSS. The asset resolver supplies those separately. |
| `config/routes.rb`, registry controller tests | Provides metadata and tarball routes with installed-version checks and strict JSON validation. | Replace this unused install path directly; translate useful validation cases into bridge tests. |
| `fixtures/dummy/package.json` | Pins `pnpm@10.34.6` (raised by #155) and contains `@rubygems/gem_npm` and `@rubygems/gem_npm_ext`, plus file/link packages. | Current fixtures do not validate pnpm 12 behavior. They provide migration cases and the `link:`/`file:` regressions. |
| `.github/workflows/main.yml:191` | Says fixture `node_modules` is committed because clean registry-backed installation needs the app running. | A clean registry-free install in CI is a concrete acceptance criterion. |
| `proscenium.gemspec`, `Rakefile:50` | Ruby >=3.4, RubyGems >=3.3.22, Rails >=7.2 and <9; ffi ~>1.17; json >=2.20 and <3. Platform build list is centralized. No executables are declared today. | Keep current compatibility bounds. Declare `exe/proscenium`. |
| `Rakefile:131` | Runs `gem build` inside `Bundler.with_unbundled_env`, because a subprocess inherits Bundler's environment. | The same rule applies to the pnpm or Bun child process. |
| `bin/verify-installed-gem:44` | Release verification loads only the installed engine library, from the installed gem's `lib` without activating it. | Extended to run the installed CLI. |
| `test/test_helper.rb:6` | Boots the dummy Rails app (`fixtures/dummy/config/environment`). | CLI tests need their own helper that loads no Rails. |

Current platform gems cover Intel/ARM macOS, x86_64/aarch64 glibc Linux and x64 Windows UCRT. The repository excludes musl for its Go C-shared/FFI engine. The Ruby CLI itself runs wherever Ruby does, but that does not extend the asset engine's platform support.

The evidence above was read from a fresh clone, not inferred from the README alone. The current Ruby/Go/Bun integration suites and release artifacts were not executed during this research. Existing CI configuration describes intended coverage; it is not proof that this checkout passes.

[Pinned repository tree](https://github.com/joelmoss/proscenium/tree/b3c795745ceb6f4810d41283616dee61865834d9). [Registry implementation](https://github.com/joelmoss/proscenium/blob/b3c795745ceb6f4810d41283616dee61865834d9/app/controllers/proscenium/registry_controller.rb#L94). [Gem import context](https://github.com/joelmoss/proscenium/blob/b3c795745ceb6f4810d41283616dee61865834d9/internal/plugin/bundler.go#L311).

## Discussion assumptions verified

| Assumption | Finding | Decision |
|---|---|---|
| Gem frontend files need copying to join JavaScript dependency installation. | Current Proscenium already reads assets from installed gem roots. The maintainer requires that behavior to remain authoritative. | Do not copy frontend assets; use dependency-only metadata contexts. |
| Gems need a package.json to serve frontend assets. | Existing gem asset serving works independently of dependency-manifest discovery. | Non-participating gems keep existing behavior and contribute no automatic JS dependency declarations. |
| Every gem that ships a package.json wants its dependencies installed. | `actiontext`, which every Rails app installs, ships a root package.json declaring `@rails/activestorage` and a `trix` peer. | Participation is opt-in. |
| Native managers can install workspace dependency graphs. | Official documentation and basic local full-package fixtures support the general mechanism. | Dependency-only workspaces are the candidate; those fixtures do not prove original-gem source resolution. |
| One package.json `workspaces` field covers pnpm. | pnpm 12.7 can create YAML if absent; existing YAML remains authoritative. The repo uses pnpm 10.x. | Register contexts in pnpm-workspace.yaml for pnpm and in root `workspaces` for Bun. |
| A metadata-only workspace exposes the gem's frontend package to ordinary JS tools. | It has no frontend files or entry points. | Ordinary native package-name imports of the gem are outside v1; use existing Proscenium gem imports. |
| Root hoisting supplies every gem's dependencies. | Local pnpm and Bun probes falsify universal root-import availability. | Associate each gem with its own native installation context; preserve distinct dependency graphs. |
| Direct workspace registration at the installed gem root is universally portable. | External roots, absolute lock paths, read-only gems and native writes remain unproven. | Prototype only if installed gems remain unchanged and committed inputs remain portable. |
| Native delegation gives identical behavior across managers. | Linkers, peer policy, scripts and lock formats differ. | Match each manager against its own baseline, never require equal trees. |
| Registering workspaces leaves an app's existing layout alone. | On Bun, registering a workspace can switch a hoisted single-package app to the isolated store ([Review probes](#review-probes-4-october-2026)). | Bun registration requires an explicit linker setting. |
| A compiled CLI is needed for startup speed. | Every run already starts under `bundle exec` with Bundler loaded; a separate binary would add a second Ruby and Bundler boot, about 0.3 s warm, to fetch data the first process already has. | The CLI is Ruby. |
| Keeping source in the gem guarantees one React instance. | Source location alone does not establish peer placement or shared module identity. | Test app/gem React identity and native peer behavior explicitly. |

Maintainer requirements: the engine registry controller is unused and is replaced directly; the hosted registry codaset uses is retired once this feature lands (see [Known consumers](#known-consumers-and-real-gem-findings)). v1 supports pnpm and Bun; npm and Yarn are unsupported. Frontend files are served from the installed Ruby gem through existing Proscenium functionality. A gem participates in automatic JavaScript dependency installation only when its author or the app opts it in; every other gem keeps current asset serving and app-level dependency lookup.

The available referenced chat included the workspace proposal, its five prototype questions, and the final brief. The thread tool exposed five turns and no older cursor, so no unseen earlier decisions are treated as established requirements.

## Measured evidence

Measurements taken while writing and reviewing this plan. They are evidence, not requirements; Stage A repeats the ones it gates on against real installed gems. The npm columns are kept as the starting point for a later npm adapter (TODOS.md).

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

What happens when someone runs the package manager directly instead of `bundle exec proscenium install`. Setup: lock created with two contexts under `.proscenium/packages/`, then `.proscenium/` removed to mimic a fresh checkout of a project that ignores it. npm 12.2.0, pnpm 12.8.1, Bun 1.4.2, offline.

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

### Review probes (4 October 2026)

Measured during the plan review; each settled a requirement below.

- **pnpm leaves a context on an old peer.** pnpm 10.34.4: after the app bumps its peer provider and re-installs, pnpm keeps the context on the old version and exits 0, with or without an app `workspace:*` edge and in a nested layout. npm and Bun kept one copy. Settles the peer-sharing check and the non-latest-pin probe in Stage A.
- **Registering a workspace can change Bun's linker.** Bun 1.3.13, single-package app with a hoisted `node_modules`: registering `.proscenium/packages/*` made Bun switch to its isolated `node_modules/.bun/` store and move the old tree to `node_modules/.old_modules-<hash>`; `[install] linker = "hoisted"` in bunfig.toml restored it. That would change every unbundled URL, manifest key and CSS/font URL in codaset. Settles the explicit-linker requirement.
- **`Bundler.load.specs` omits excluded groups.** With `BUNDLE_WITHOUT=development`, 94 of 110 locked gems were loaded. Settles the use of `Bundler.locked_gems` for orphan checks.
- **Parsing manifests at boot is cheap.** Ruby parsed 184 manifests averaging 1.2 KB in about 31 ms. Settles hashing the projection rather than raw manifest bytes.
- **Rails ships a package.json.** `actiontext` 8.1.3.1 ships a root package.json declaring `@rails/activestorage` and a `trix` peer. Settles opt-in participation.
- **A second Ruby boot costs about 0.3 s.** `bundle exec ruby -e 'Bundler.load.specs.size'` in `fixtures/dummy` took 0.30 s warm (0.60 s cold). A compiled CLI launched from `bundle exec` would pay this again to query Bundler. Settles the Ruby CLI.

## Scope and compatibility policy

V1 includes the Ruby CLI with four commands (`install`, `install --frozen`, `inspect` and `gem check`), opt-in gem discovery, one dependency manifest per participating gem, dependency-only metadata projection, workspace registration, native locking through pnpm and Bun, dependency lookup integration in the asset engine, adoption, a frozen CI drift check, a consumer quickstart and a gem author guide. Existing gem asset serving is reused for every gem. pnpm and Bun are independent adapters with independent qualification status.

V1 excludes copying or mirroring gem frontend files, turning gems into complete native JavaScript packages, a new Ruby or JS resolver, registry proxying, cross-manager lockfile conversion, package publishing, downloading runtimes, implicit gem frontend builds, and multiple dependency manifests inside one gem. npm and Yarn are unsupported in v1, in every version and linker mode; each would be a later adapter with its own evidence. Also out of v1: context name overrides, a Rails app nested inside an enclosing JS workspace, Bun projects with only a binary `bun.lockb`, a manager-independent dependency URL scheme, and the commands and recovery tooling listed under "Deferred package manager commands" in TODOS.md. V1 does not expand the asset engine's platform support.

### The pilot

v1 is a pilot. Stage A starts in london with a hand-written hue context on pnpm, then moves to codaset with proscenium-ui on Bun 1.4 or newer. Stage A has no time box: it ends on evidence, not a date. Kill criterion: if a context cannot give hue its dependencies and one React instance, in bundled and unbundled mode, Stage A is NO-GO and the design reopens. The bridge stays labelled experimental for outside gem authors until at least one gem outside the maintainer's apps adopts it.

### Compatibility

| Family | Qualification target | Shipping rule |
|---|---|---|
| Bundler | The repository's Ruby 3.4 baseline; Ruby 4.0 in Stage D. Bundler version selected by the project's own lock. | Test group and platform discovery on each qualified version. Never upgrade Bundler. |
| pnpm | 11.x and 12.x, with 11 as the CI floor. pnpm 10 is not supported: after an app upgrades a shared peer, it leaves a gem's context on the old copy (Stage A), and 11 and 12 do not. london and platform run pnpm 10 today and move to 11 before adopting (Stage E). 11 reaches end of life on 2027-04-30. | Registration always goes through pnpm-workspace.yaml. |
| Bun | 1.4.x, with 1.4.0 as the floor. Bun publishes no support policy and releases only its latest version (no 1.3.x release after 1.4.0 on 2026-08-20). | Bun 1.3.x cannot see workspaces under a dot directory such as `.proscenium/packages`. Registration requires an explicit `[install] linker` in bunfig.toml and an explicit `trustedDependencies` array in package.json. Only the text `bun.lock` is supported. Hoisted and isolated linkers are qualified independently. |
| Node.js | 22, 24 and 26 | Supported LTS/current lines only. Node 25 reached end of life on 2026-06-01. |

**Support rule.** Proscenium supports the pnpm and Bun lines in the capability table, plus one CI floor per manager, and only lines their owners still maintain at the time of each Proscenium release. Qualification hosts are the hosts those apps develop and deploy on, recorded in Stage A. A machine-readable capability table committed with the tests is the source of truth: PR CI pins exact manager versions from it, and a nightly canary runs each line's newest patch. A line its owner will drop by the next Proscenium release triggers an `install` warning naming the line one release ahead, and the CHANGELOG lists it; the upgrade guide gives the tool-and-lock migration order and its rollback boundary. The repository's own pins were outside this rule (CI on Bun 1.3.13, fixtures on pnpm 10.4.0 and 10.6.0); #155 raised them to Bun 1.4.2 and pnpm 10.34.6. Moving the fixtures to pnpm 12 waits for this feature: pnpm 12 records itself in the lockfile, and regenerating `fixtures/dummy`'s lock needs the dummy app's own registry running.

These are targets, not verified compatibility. An unqualified manager version produces an actionable error; `--experimental-manager-version` allows one for development only and is rejected under `--frozen`. A project selecting Yarn (`packageManager` field, `yarn.lock` or `.yarnrc.yml`) or npm (`packageManager` field, `package-lock.json` or `npm-shrinkwrap.json`) gets the unsupported-manager error (exit 3) before any write. The message offers two ways on: switch to pnpm or Bun, or keep that gem's JavaScript dependencies app-managed as today.

**Manager selection.** Use `--manager pnpm` or `--manager bun` when supplied; otherwise the root `packageManager` field; otherwise exactly one recognized lockfile (`pnpm-lock.yaml` or `bun.lock`). Infer this without a setup prompt when unambiguous. Conflicting signals or multiple lockfiles produce an actionable error. A project with no signal must pass `--manager`, and the error says so. Preserve Corepack, mise and Volta policy, and never choose a manager merely because it is installed. The selection is not stored in Proscenium settings.

## Architecture and persistent artifacts

The developer installs Ruby gems with `bundle install`. `bundle exec proscenium install` then reads the installed bundle in process, projects each participating gem's manifest into dependency-only metadata, writes the contexts, runs pnpm or Bun, and validates the result. Gem assets remain at Bundler's installed roots throughout. JS changes do not cause Ruby re-resolution. An updated gem may change its JS dependencies, so the command runs again after every Gemfile change, and the engine reports a stale context until it does.

```text
Gemfile + gemspec + Gemfile.lock
               |
      bundle install (native Bundler)
               |
        installed Ruby gems
          /             \
frontend files       package.json of gems that opt in
stay in gem root             |
          |       bundle exec proscenium install
          |       (Ruby, reads Bundler in process)
          |                  |
          |      dependency-only contexts, committed
          |      .proscenium/packages/<gem>/package.json
          |                  |
          |      root workspace registration + app package.json
          |                  |
          |              pnpm / Bun
          |                  |
          |      native JS lock + dependency layout
          |                  |
existing Proscenium asset engine <- gem dependency-context map
               |
         current asset URLs

Gems that do not participate: existing asset serving + app dependency context.
```

| Artifact | Ownership | Commit policy |
|---|---|---|
| Gemfile, gemspec, Gemfile.lock | User and Bundler | Normal project policy; no Proscenium Ruby lock serialization |
| Installed gem frontend files and package.json | Bundler/gem author | Read in place; no Proscenium copies or writes |
| Root package.json and pnpm-workspace.yaml | User and native manager | Commit. Proscenium adds only the `.proscenium/packages/*` registration, once, as a textual splice |
| Native lockfile (`pnpm-lock.yaml` or `bun.lock`) | Selected native manager | Commit; written only by the manager; no format conversion |
| `proscenium.json` | Optional overrides | Absent with defaults; commit explicit overrides only; no dependency declarations |
| `proscenium.bridge.json` | Descriptor receipt, only if Stage A shows one is needed | Commit without hand editing; no frontend inventory or JS transitive graph |
| `.proscenium/packages/<gem>/package.json` | Generated dependency-only context | **Commit.** Byte-stable (fixed key order, trailing newline, no timestamps or host paths), so an unchanged gem never churns it. Committing it lets a plain native install on a fresh checkout see every gem ([Fresh-checkout probes](#fresh-checkout-probes-3-october-2026)) and puts a gem upgrade's JS dependency changes in the pull request. No frontend files. |
| `exe/proscenium` and `lib/proscenium/cli/` | The Ruby CLI, shipped in every Proscenium gem | Distributed with the gem; nothing to build or download |
| `.proscenium/lock`, `.proscenium/holder`, `.proscenium/manager`, `.proscenium/installing` | Machine-local CLI state | Ignored |
| `.gitignore` | User | The first install adds `.proscenium/*`, `!.proscenium/packages/` and `.proscenium/packages/*/node_modules/`, and reports them with the other owned edits |

`.proscenium/packages/` is a directory Proscenium owns. Every entry there is a generated context, and a user package placed there is a participation error. Context paths are stable and project-relative; they contain gem identity, never machine-specific installation prefixes, platform names or random hashes. Native managers own any dependency files and links they create inside a context; Proscenium never puts gem frontend files there. When Bun switches linker it leaves `node_modules/.old_modules-<hash>` behind; the app's `node_modules` ignore rule covers it, and `install` adds one if the app has none.

A generated context looks like this (hue's shape):

```json
{
  "name": "@rubygems/hue",
  "private": true,
  "description": "Generated by Proscenium from the hue gem. Do not edit; run bundle exec proscenium install.",
  "dependencies": {
    "sourdough-toast": "github:<owner>/sourdough-toast#<ref>"
  },
  "peerDependencies": {
    "react": "^18.3.1"
  },
  "proscenium": {
    "projection": "dependency-context-v1",
    "projectionSha256": "<hex>"
  }
}
```

`proscenium.json` is optional and generated only when the app asks for an override. Its published JSON schema has these keys:

```json
{
  "schema": 1,
  "gemOverrides": {
    "hue": { "participate": true }
  },
  "rubyGroups": ["default", "development", "test"],
  "platforms": ["arm64-darwin", "x86_64-linux-gnu", "x64-mingw-ucrt"]
}
```

`gemOverrides.<gem>.participate` opts a gem in (`true`) or out (`false`). `rubyGroups` overrides the default discovery universe, which is every Gemfile group independent of `BUNDLE_WITHOUT`; it never changes what Bundler installs. `platforms` overrides the default, the declared platforms in Gemfile.lock. Gems that are locked but not installed, because they sit in an excluded group or belong to another platform, follow the [production rule](#installation-and-locking-algorithm). The context directory and projection version are fixed, not configurable.

**Descriptor receipt.** Stage A decides whether a receipt is needed. It is kept only if committed native inputs cannot detect a changed locked gem source or revision, a changed projection or projection version, or a changed registration; Stage A demonstrates each of those drift cases one at a time, without committed host paths. Without a receipt, locked source identity comes from Gemfile.lock alone, and every requirement below that mentions the receipt does not apply. If it is kept, it binds credential-free source identity to each context and records no installed absolute roots, frontend digests or copied payload:

```json
{
  "schema": 1,
  "projection": "dependency-context-v1",
  "packages": [{
    "gem": "widgets",
    "rubyVersion": "2.0.0.pre",
    "source": { "type": "git", "revision": "<full revision>" },
    "context": ".proscenium/packages/widgets",
    "projectionSha256": "<digest>"
  }]
}
```

## Gem author contract and dependency metadata

### Opting in

A gem participates in JavaScript dependency installation only when one of these opts it in:

- **The author**, by setting gemspec metadata `spec.metadata['proscenium.dependencies'] = 'true'`. An optional `proscenium.frontend_root` metadata string selects the relative directory that holds the manifest; it MUST resolve inside the gem. It does not move files or redefine asset-serving roots.
- **The app**, for a gem whose author has not opted in, with `"gemOverrides": {"<gem>": {"participate": true}}` in `proscenium.json`.

`"participate": false` excludes an opted-in gem; an excluded gem keeps today's app-context lookup and gets no context. A gem that has not opted in never gets a context and keeps today's behavior, whether or not it ships a package.json; if its package.json is invalid, `install` warns and skips it rather than failing. `inspect` lists the gems that ship a root package.json but have not opted in, so an app can opt them in deliberately. Opt-in is deliberate because Rails itself ships manifests: `actiontext`, which every Rails app installs, declares `@rails/activestorage` and a `trix` peer.

An opted-in gem whose selected manifest is missing, unreadable or invalid is a participation error, never a silent skip. Withdrawing participation (removing the metadata or the override) removes the gem's context and its native lock entries on the next `install`.

### Packaging

Authors include frontend files and the manifest in the built gem's `spec.files`. Bundler installs them together; Proscenium serves the files in place. A manifest present only in the source checkout but missing from the built gem cannot drive consumer installation. Git-source gems are the exception: Bundler installs them as full checkouts, so their manifest is on disk whatever `spec.files` says. Discovery reads the installed root in both cases, and `gem check` warns when a manifest would be lost from the built gem. The gem author guide's release checklist tells authors to run `proscenium gem check` before building or releasing a gem.

### Context identity and version

The context name is `@rubygems/<gem-name>`. It must be a valid npm package name; a gem whose name is not (one with uppercase letters, say) gets a participation error naming it, and there is no name override in v1. The name is an internal graph identity, not a promise of an importable package for native JS tools.

Per decision D1, the generated context omits `version`: the gem's manifest version is neither required nor copied, so a missing or stale one (hue, proscenium-ui) is not an error, and a Ruby version is never written there (pnpm 10 and 11 reject Ruby prerelease syntax such as `0.5.3.pre1`). Every reference Proscenium generates to a context uses `workspace:*`, which pnpm and Bun both resolve to the local workspace whatever version the context declares.

### The `dependency-context-v1` projection

The projection generates installation metadata only: the context `name`, `private: true`, the generated `description`, runtime `dependencies`, `peerDependencies`, `peerDependenciesMeta`, `optionalDependencies`, the engine/OS/CPU/libc constraints, and the `proscenium` block holding the projection version and `projectionSha256`. It excludes gem-author devDependencies, lifecycle and task scripts, nested workspaces and nested `packageManager` selection. It does not expose `main`, `module`, `browser`, `exports`, `imports`, `types`, `bin`, `sideEffects` or `files` as pointers to nonexistent workspace assets. The original package.json stays in the gem for the asset engine's own lookups. For each field the projection drops, the plan classifies it either as preserved because the engine reads the original package.json, or as an author-contract restriction, and a fixture per class proves the classification (C20). `inspect` reports every projection rule it applied.

The projection and its hash have one owner: Ruby code beside `lib/proscenium/bundled_gems.rb`, which both the CLI and the engine call. `projectionSha256` hashes a fixed-field encoding of the projected fields (not `JSON.generate` output), so edits to scripts, devDependencies or `version`, and CRLF checkouts, do not change it. Shared golden vectors cover key order, escapes, absent versus empty fields and every allowed `json` gem version. A projection version change between Proscenium releases is named in the CHANGELOG, and `install --frozen` reports it as "context projection changed from <old> to <new>; run bundle exec proscenium install and commit .proscenium/packages" rather than as a generic drift error.

### Dependency specifications

Each dependency spec in a participating manifest is checked against an allow-list: semver ranges, dist-tags, `npm:` aliases, `github:owner/repo` with an optional `#<ref>`, `git+https://` and `git+ssh://` URLs with an optional `#<ref>`, `https://` tarball URLs, and the gemspec-backed cross-gem reference below. `catalog:`, `portal:`, `patch:`, any other `workspace:`, `file:` and `link:` are participation errors. `npm:` alias targets are normalized before the manager runs, and an alias whose target is under `@rubygems/` is a participation error. The install summary lists every Git or URL dependency a gem introduces.

Relative `file:` and `link:` dependencies are rejected because relocating metadata changes their base directory; Proscenium never rewrites them into host-specific absolute paths.

App-level overrides, resolutions, patches, catalogs and script approvals remain authoritative. A gem cannot promote its own install policy into the app. Nested workspace declarations are a participation error. Unknown source metadata remains inert data and is never copied into executable bridge policy.

Proscenium MUST NOT run gem frontend installation or build hooks. The context contains no scripts or `binding.gyp`, and no frontend source is placed in its directory. A gem declaring required install or prepare hooks, or implicit native frontend builds, gets an author-contract error rather than an incomplete build. Assets needed by consumers must already ship in the gem. Lifecycle scripts of ordinary third-party dependencies follow the app's native script policy ([Security](#security-and-failure-recovery)).

### References between gems

A gem's manifest may reference another gem's context (`@rubygems/<other>`, as a dependency or a peer) only when `<other>` is a runtime dependency in that gem's gemspec **and** `<other>` participates. Bundler metadata says whether the gemspec dependency exists, which makes Bundler the single authority for gem-to-gem compatibility: `<other>` is guaranteed to be locked, and its version is already checked against the gemspec constraint. The JS-side range is therefore dropped, not translated (contexts carry no version, per D1), and the reference is rewritten to `workspace:*`.

- A reference to a gem that is not a gemspec runtime dependency is a participation error naming both gems and the gemspec line to add.
- A required reference to a gemspec dependency that has not opted in, or that the app excluded, is a separate participation error saying the target does not participate and how to opt it in.
- An optional peer (`peerDependenciesMeta.<name>.optional`), which a gemspec cannot express, is linked when the target participates and left out of the projection when it does not, which is what native optional-peer handling would produce for an absent provider. Bundler does not check an optional peer's version, so `inspect` shows its declared range beside the target's locked version.

A reference is never rewritten unless it is backed this way, because a reference to a package with no workspace context can resolve from a registry ([Version probes](#version-probes-3-october-2026)). Cross-gem declarations must never fetch a gem-backed package from a registry.

### Participation errors and consumer escapes

When a participation error comes from a gem's own manifest (a nested workspace, an install hook, an unbacked `@rubygems/*` reference, a rejected protocol), the consumer-facing message names the gem, the cause and the fix for the gem author, and then gives the consumer escape: a copyable `"gemOverrides": {"<gem>": {"participate": false}}` snippet for `proscenium.json`, which restores today's app-context behavior for that gem. It states that the app must then declare that gem's JS dependencies itself. A gem that declares React as a plain dependency gets the author-contract diagnostic "declare React as a peer" (C43), and the guide names native `overrides` in pnpm and Bun as the consumer's way to dedupe it meanwhile.

[RubyGems specification and packaged file contract](https://guides.rubygems.org/specification-reference/). [Node package entry points and exports](https://nodejs.org/api/packages.html).

## Workspace bridge feasibility and alternatives

| Strategy | Native dependency graph and lock integration | Asset-serving boundary and portability | Disposition |
|---|---|---|---|
| Generated dependency-only workspace manifests | Stable project-relative native inputs; each gem retains its own graph context | Proscenium serves original installed-gem files; issuer lookup and peers need proof | Primary Stage A hypothesis, not yet verified. |
| Direct workspace at installed gem path | Depends on external workspace recognition and portable locked paths | Assets stay in gem; native writes to shared/read-only roots may violate the contract | Prototype comparison only; reject if it writes to gem roots or commits host paths. |
| Metadata-only local file/tarball descriptor | May provide alternate native consumer semantics and peer placement | Contains only dependency metadata, never gem frontend payload | Conditional fallback candidate; must prove locks, context lookup and portability. |
| Copied frontend workspace or source façade | Could expose a complete package to native JS tools | Duplicates or mirrors assets and changes their source location | Excluded by the confirmed requirement. |
| Shadow project or merged dependency manifest | Installs against a different graph; may flatten distinct contexts | Native root-lock, peer, script and tooling behavior can diverge | Reject as silent fallback. |
| New registry shim or custom package resolver | Defeats native-manager/no-registry requirements | Adds a service or dependency resolver | Out of scope. |

**Registration.** The first install adds `.proscenium/packages/*` to pnpm-workspace.yaml `packages` (pnpm) or to the root package.json `workspaces` (Bun), preserving existing patterns, exclusions, catalogs, overrides and build policy. It is a textual splice that preserves key order, indentation, CRLF line endings, YAML comments and the trailing newline; golden tests cover tabs, four-space indent, CRLF, YAML comments and the `workspaces: {packages: []}` form. Broad globs that would include the contexts twice are diagnosed from the manager's own enumerated workspace set, and exclusions are never removed. Creating pnpm-workspace.yaml for an app that keeps its pnpm settings in `package.json#pnpm` must not change how those settings are read; Stage A asserts it for london.

**Bun linker and script trust.** Registering a workspace can switch a hoisted Bun app to the isolated store ([Review probes](#review-probes-4-october-2026)), and linker policy is never changed silently. So `install` refuses to register a Bun app whose bunfig.toml does not set `[install] linker`, and the error explains both values and what each does to URLs. It also refuses one whose package.json has no explicit `trustedDependencies` array (an empty one is fine), so that Bun's default trusted list never applies to packages a gem introduces. Under the hoisted linker, a participating gem's lookup never takes the legacy `node_modules/@rubygems/<gem>` branch; a test asserts it.

**No app edge by default.** The app's package.json gets no dependency edge to a context. Stage A runs each pnpm and Bun line with the context referenced from the app and unreferenced, with each manager's default peer settings (including pnpm's `auto-install-peers`), and records whether an unreferenced context installs its dependencies and gets the app's React. An app edge is added only if Stage A shows it is required, as a one-time visible initialization edit.

**Adoption.** An app has adopted the bridge when its committed registration contains `.proscenium/packages/*`. The directory's existence is not the signal, because Git drops an empty directory; an adopted app with zero contexts, or one whose last participating gem was removed, stays adopted.

**Layouts.** A Rails app nested inside an enclosing JS workspace is rejected with an unsupported-configuration error naming the layout: its dependency files would resolve outside `Rails.root`, where the middleware cannot serve them, and two apps could share one native lock. Stage A records whether london, platform or codaset use such a layout.

App source addresses gem assets through existing `@rubygems/<gem>/...` imports, whether or not the gem participates. The generated context is not a complete importable JS package; do not advertise direct Node or native-runner imports of gem assets, or create app dependency edges solely to make those assets visible. Proscenium's Bun test harness remains an engine-specific integration. Apps declare peer providers such as React in their own package.json when sharing is required.

Native workspace selection, transitive dependency resolution, peer diagnostics, optional omission, engine behavior and linker configuration are preserved. Proscenium MUST NOT flatten gem dependencies into the app's dependencies; that would lose distinct dependency and peer contexts. Each adapter must prove context attachment to the root graph, package-local lookup without accidental hoisting, and any declared cross-gem edges, without changing global linking policy.

Yarn is unsupported. Adding it later needs more than an adapter: Plug'n'Play needs the Yarn dependency-tree API, issuer-aware lookup, zip and unplugged file access, source-map support and stable virtual asset URLs in the engine, and silently forcing `nodeLinker: node-modules` would be prohibited.

[pnpm workspace contract](https://pnpm.io/workspaces). [Bun workspace guide](https://bun.sh/guides/install/workspaces). [Bun isolated installs](https://bun.sh/docs/pm/isolated-installs). [pnpm 12.7 release](https://pnpm.io/blog/releases/12.7).

## CLI contract

### Shape

The CLI is Ruby. `exe/proscenium` is a Ruby executable declared in the gemspec (`spec.bindir = 'exe'`, `spec.executables = ['proscenium']`; neither exists today), with its code under `lib/proscenium/cli/`. It ships as plain Ruby files in every Proscenium gem, platform and plain alike, so a Git or path source of Proscenium has the CLI with no build step, and there is nothing to compile or download.

It runs under `bundle exec`, so Bundler has already loaded and checked the app's bundle. The CLI reads that bundle in process through `lib/proscenium/bundled_gems.rb`, the same reader the engine uses, so the two never disagree about which gems exist. It requires only `proscenium/bundled_gems` and `lib/proscenium/cli/`, never `proscenium` itself (which loads ActiveSupport), Rails, FFI or the engine library. A test asserts that ActiveSupport, Rails, FFI and `Proscenium::Builder` are not loaded after each command, with a seeded `require 'proscenium'` as its positive control.

The project is the active bundle's `Bundler.root`. Running from a subdirectory works, and a `BUNDLE_GEMFILE` naming another app selects that app, so contexts can never be generated from one app's bundle into another app's tree. There is no `--project` option.

The bundle must already be installed: `bundle install` after any Gemfile change, as `bundle exec` itself requires. `bundle exec` guarantees the active groups are installed; locked gems outside them follow the [production rule](#installation-and-locking-algorithm). The CLI never runs Bundler.

`proscenium gem check` is the exception: it needs no bundle. It loads the gemspec with `Gem::Specification.load`, so a gem author can run `proscenium gem check` after `gem install proscenium`.

### Commands

| Command | Contract and allowed writes |
|---|---|
| `proscenium install` | On the first non-frozen run in a project, prints the owned edits (workspace registration and `.gitignore` lines) as a unified diff, then writes them and creates `.proscenium/packages/`. Writes changed contexts, removes orphaned ones, runs the native install and validates the result. May update the native lock when contexts changed; never updates all dependencies. |
| `proscenium install --frozen` | Writes nothing. Regenerates every context in memory, compares it with the committed one, requires the registration and the native lock, then runs the manager's frozen install. Any difference fails (exit 4) before the manager starts. |
| `proscenium inspect [gem]` | Read-only. For each participating gem: its locked source, the projection rules applied, the committed context and whether it is stale, `projectionSha256`, the Git and URL dependencies it introduces, optional peer ranges beside the target's locked version, and the linker in use. Lists gems with a root package.json that have not opted in. Redacts credentials. With `--json` it prints one JSON document. |
| `proscenium gem check [path]` | Author check; needs no bundle. Defaults to the gem in the current directory, or takes a source directory or a built `.gem`. Validates the manifest against the projection rules (hooks, the dependency allow-list, nested workspaces, cross-gem references, React declared as a plain dependency), the `proscenium.*` metadata keys, and that the manifest and frontend files are in `spec.files`. For a built `.gem` it reads the archive's metadata without unpacking frontend files. Runs no author builds. |

`install` is documented as the only command a developer needs. Other commands are deferred; TODOS.md lists them with the reasons.

### Options, environment and configuration

One reference table in the guide defines every flag, environment variable and configuration key with its exact spelling. It is this table:

| Name | Applies to | Meaning |
|---|---|---|
| `--manager pnpm`, `--manager bun` | `install` | Selects the manager when signals are absent or conflicting. |
| `--frozen` | `install` | Writes nothing; fails (exit 4) on any drift. |
| `--production` | `install` | Omits app devDependencies using the manager's native semantics and honors existing Ruby group config. Never edits manifests. |
| `--offline` | `install` | The manager fetches nothing; fails if the manager cannot enforce that. Proscenium does not sandbox Gemfile evaluation, native-extension builds, manager plugins or permitted scripts; a stronger guarantee needs external network isolation. |
| `--experimental-manager-version` | `install` | Allows a manager version the capability table does not qualify, for development only. Rejected with `--frozen` (exit 3). |
| `--js-arg <arg>` | `install` | Repeatable; passes one argument to the manager's install command. Rejected with `--frozen` or `--offline`. |
| `--json` | all | Newline-delimited JSON events on stdout (`inspect`: one document). |
| `--quiet`, `--verbose` | all | Less or more human output. |
| `--version` | all | Prints the Proscenium version. |
| `PROSCENIUM_STALE_CONTEXT=warn` | engine | Downgrades the engine's stale-context build error to a logged warning. A temporary escape for an incident, documented as such. |
| `proscenium.json` `schema`, `gemOverrides.<gem>.participate`, `rubyGroups`, `platforms` | CLI and engine | See [Architecture and persistent artifacts](#architecture-and-persistent-artifacts). The file has a published JSON schema. |
| gemspec metadata `proscenium.dependencies`, `proscenium.frontend_root` | CLI and engine | See [Opting in](#opting-in). |

### Output, exit codes and errors

By default stdout carries the human summary and the manager's own output goes to stderr. `--json` switches stdout to newline-delimited, schema-versioned events with the fields `schema`, `event`, `phase`, `status`, `code`, `message`, `fix`, `manager` and optional sanitized `details`.

A successful install names each participating gem with its manager and dependency count, lists the Git and URL dependencies gems introduced, and lists the exact files to commit: changed contexts, the registration, `.gitignore` and the lockfile.

Exit codes: 0 success; 1 unexpected internal error, which always prints a bug-report hint; 2 invalid input; 3 unsupported configuration; 4 frozen drift; 5 source or integrity failure; 6 native tool failure; 7 busy project; 8 interrupted. The native exit status goes in `details`. An install failure is never treated as permission to change managers or regenerate locks.

Every error states the problem, its cause and the fix (a command or a file edit), and links its guide anchor where one exists. Each has a stable code such as `PSM-E-PARTICIPATION-HOOK`, carried in the JSON event with a `fix` field. Golden-output tests pin the human text and the JSON for every code and every exit status. Specific messages:

- Frozen drift prints a unified diff of each differing context and says when a context was edited by hand.
- The unsupported-manager error offers switching manager or keeping gem dependencies app-managed.
- Exit 7 names the command already running and says to wait for it; exit 8 and the engine's install-in-progress refusal both print `bundle exec proscenium install`.

### Running pnpm and Bun

The CLI starts the manager with `Process.spawn` and an argument array (never a shell, so package names are never interpolated into one), with `chdir` set to `Bundler.root` and streamed output. The child's environment is built inside `Bundler.with_unbundled_env`, as `Rakefile` does for `gem build`, and then native configuration overlays are applied, so a dependency lifecycle script that runs Ruby sees the same environment as a direct native install. Manager executables are resolved explicitly, including Windows `.cmd` shims through `PATHEXT`, and their versions are checked against the capability table. INT and TERM reach the child; the CLI waits for it, then maps its status to the exit codes above, with an interrupted install exiting 8.

### Project lock

`install` takes `File#flock(File::LOCK_EX | File::LOCK_NB)` on `.proscenium/lock` and exits 7 if another install holds it. The lock is released by the operating system when its holder dies, so there is no stale-lock reclamation. The lock's file descriptor is passed to the manager child, so a manager that outlives a killed CLI still holds it: killing the CLI with SIGKILL and retrying at once exits 7 until the manager finishes. Windows Ctrl-C delivery and lock release are qualified on windows-latest, not assumed from the Unix behavior. (Stage D: Ruby on Windows cannot hand a child a descriptor, so there a killed CLI releases the lock while its manager runs on. The CLI records the running manager's pid in `.proscenium/manager`, and an install that finds that process alive exits 7, which keeps the guarantee. The console delivers Ctrl-C and Ctrl-Break to the manager itself, so on Windows the CLI only notes the interruption, waits, and reports exit 8.) Running a native manager command by hand while a build runs is unsupported, as it is today.

## Installation and locking algorithm

1. **Start.** Take the project from `Bundler.root`. Reject a Rails app nested inside an enclosing JS workspace and a Bun project with only `bun.lockb` (exit 3). Select the manager, check its version against the capability table, and for Bun check the explicit linker and `trustedDependencies`. Validate manifest formats and owned paths before any mutation. Take the project lock (exit 7 if busy).

2. **Read the bundle.** Through `bundled_gems.rb`, in process: the locked gems (`Bundler.locked_gems`; when it is nil because there is no lockfile, skip the orphan check and keep the existing "No gems in your Gemfile" path), the installed specs and roots (`Bundler.load.specs`), gemspec metadata and declared platforms. Work out the participating set. **Production rule:** a locked gem that is not installed, because it sits in a group excluded by `BUNDLE_WITHOUT` or belongs to another platform, has no source to read. Its committed context is trusted, its projection comparison is skipped, and each skip is reported. That is why `install --frozen --production` and `--offline` need no sources for excluded gems and make no network requests (C32); the non-production CI run is the authoritative drift check.

3. **Validate and project.** For each participating, installed gem: read its manifest, apply the opt-in rules, the dependency allow-list, alias normalization, the cross-gem rules, the hook and nested-workspace rules and the name check, and produce the context bytes and hash. Detect workspace collisions before the manager runs. Where the sources of other platform variants of a gem are available (the Bundler cache), compare participation eligibility and projected metadata across variants; differing declarations are unsupported until a profile-aware lock design exists (C33). Where they are not available, report the skip.

4. **Compare or write.** In frozen mode, compare the in-memory contexts with the committed ones and check the registration and the native lock; an orphaned context (one whose gem left the bundle, stopped participating or lost its manifest) or any difference fails with exit 4 and a diff, before the manager starts. In non-frozen mode, write `.proscenium/installing`, then the first-run registration and `.gitignore` lines after printing them as a diff, then each changed context atomically (write to a temporary file, then rename). Unchanged contexts are left untouched so their native links survive. Remove orphaned contexts here, so the same run's native install refreshes the lock.

5. **Run the manager** in the project root: `pnpm install` or `bun install`, and in frozen mode `pnpm install --frozen-lockfile` or `bun install --frozen-lockfile`, qualified per version, with the native equivalents of `--production` and `--offline`. Native auth, registries, proxies, private packages, patches, overrides and linking configuration are respected. Tree-affecting flags used to create the lock are preserved.

6. **Validate.** Scan the native lock and fail (exit 5) if any `@rubygems/*` entry resolves to a registry tarball. Check that the manager's enumerated workspace set contains every context; Bun exits 0 when contexts are missing, so the CLI checks this itself. Check peer sharing: for each peer a context declares whose package the app also declares (sharing intended), the real path resolved from the context must equal the one resolved from the app root, otherwise exit 5 naming the package. Absent optional peers, gem-backed peers and intentionally distinct providers (C13) are compared with the native baseline instead. An age-gate failure such as pnpm's `minimumReleaseAge` names the gem context that introduced the package. Then remove `.proscenium/installing`, release the lock and print the summary.

A no-op install leaves native locked choices, contexts and user manifests byte-identical. First registration, projection changes, additions and removals may cause necessary native lock churn. Changes only to a gem's frontend files are handled by the asset engine and never need an install.

Frozen mode fails for a missing registration, a changed or orphaned context, a changed native lock input, an unqualified manager change or an experimental override. It never writes the committed contexts. It may download locked dependencies when online.

Do not register contexts temporarily, generate a lock against them and then remove the registration; that leaves native inputs inconsistent. Because contexts are committed, a native frozen install in CI sees the same inputs as `install --frozen`. A plain native install alone does not prove the contexts match the locked gems, so CI runs `bundle exec proscenium install --frozen`.

**Recovery.** An interrupted install leaves `.proscenium/installing`, and the engine refuses to build until it is gone. Re-running `bundle exec proscenium install` recovers: context writes are atomic and the lock serializes installs, so the run is idempotent. Owned committed files are restored with Git. Ruby gems may be installed while the JS install failed; the CLI says so and never claims a cross-ecosystem transaction.

[pnpm installation and frozen flags](https://pnpm.io/cli/install). [Bun native lockfiles](https://bun.sh/docs/pm/lockfile). [Bundler deployment behavior](https://bundler.io/guides/deploying.html).

## Asset resolver integration

### Engine inputs

The engine's only inputs are committed files and Bundler. The Ruby side builds the gem-to-context map from `Bundler.load.specs` (installed roots), `Bundler.locked_gems` (orphan checks), participation (gemspec metadata and `proscenium.json`), a listing of `.proscenium/packages/` and each installed participating gem's projection hash, computed by the same Ruby code the CLI uses (parsing every manifest costs about 31 ms for 184 of them). It passes the map to Go beside `RubyGems` in both config sites, `lib/proscenium/builder.rb` and the Bun daemon's `lib/proscenium/runtime/server.rb:235`; a Go test asserts the key arrives. (Stage C: the daemon builds and resolves through `Builder`, and its JS side never read the handshake's `rubyGems`, so `Builder` is the one site. The CLI writes contexts, the lock and the marker at `Bundler.root` (C53), so the engine reads them there too, not at `Rails.root`; the two differ for this repo's dummy app and under Appraisal.) Each entry holds the gem identity and root, the context path, the linker and the projection hash. The engine therefore works after a plain native install on a fresh checkout. It reads no other CLI state except `.proscenium/installing` and the lock. It makes no Go call at Rails boot, because Go's runtime cannot survive Puma's `preload_app!` fork.

### Adoption and staleness

Before an app adopts the bridge, and in any Yarn or npm project, the engine keeps today's behavior for every gem and logs one notice per process at boot: it names the gems that opted in and the command `bundle exec proscenium install` (for Yarn or npm: that the manager is unsupported and gem dependencies stay app-managed). Upgrading Proscenium on an un-adopted app never breaks its build (C52).

After adoption, a stale context is a build error in every environment, naming the gem and `bundle exec proscenium install`. A context is stale when:

- an installed gem participates but has no committed context;
- a committed context belongs to a gem absent from Gemfile.lock (checked against `Bundler.locked_gems`, never `Bundler.load.specs`), or to an installed gem that no longer participates; or
- an installed participating gem's projection hash differs from its context's `projectionSha256`.

A context for a locked gem in a group excluded by `BUNDLE_WITHOUT` is never stale. An error rather than a warning is deliberate: a stale context silently resolves a gem's imports against the wrong dependency graph, and only apps that adopted the bridge can hit it. `PROSCENIUM_STALE_CONTEXT=warn` exists for incidents. In development and test, staleness and the pre-adoption notice are logged once at Rails boot (Ruby only), shown in the development error page body, and reported by `inspect`. At deploy time `assets:precompile` is the drift gate: the error fires there, not at the first request.

### Install in progress

While `.proscenium/installing` exists, or the project lock is held (a non-blocking probe), the engine refuses every build and resolve request, including before the Bun daemon returns a cached result, and names `bundle exec proscenium install`. When the marker disappears, the engine builds a new mapping generation.

### Lookup

One issuer-aware dependency lookup serves every path that resolves a participating gem's external import: the `bundler.go:311-337` branch, the `bundless.go:384-417` chain, the bare-with-extension shortcut at `bundless.go:345-349`, the CSS-module and SVG resolve at `bundless.go:46`, and CSS mixin lookup through `resolver.Resolve` (`internal/css/mixins.go:60`). This subsumes the TODOS.md item "Resolve a gem's bare-with-extension imports against the gem when unbundling" for participating gems.

An external import from a participating gem's file resolves once, as if the importer lived in its context directory (`.proscenium/packages/<gem>/`), and that replaces the whole existing chain, including the first step, whose walk-up from an in-tree path gem would reach the app's `node_modules` before the context. There is no retry against the app root. Ordinary `node_modules` walk-up from the context directory still applies; that walk-up is how hoisted copies are found. The context directory is the only lookup base that gives the right answer on every adapter: pnpm and Bun's isolated linker put a gem's dependencies under the context only and leave the root without them ([Layout probes](#layout-probes-3-october-2026)). Falling back to the root would silently pick the app's version of a package the gem pinned differently. For a participating gem, a resolution miss is a named error naming the gem and the package, never converted into a browser external. Non-participating gems keep both existing chains unchanged.

Relative imports, CSS references, source reads and file ownership continue to resolve from the original installed gem paths through the current engine. Package-internal imports and self references keep their current source-package semantics; only external package lookup changes base. Existing gem import and entry-point behavior, esbuild conditions and legacy deep paths stay as they are. Engine debug logging (`cfg.Debug`) records each bare import routed to a context, with the gem and the resolved path.

### Identity and URLs

A package is identified by the real path of the resolution result (EvalSymlinks on the resolved file, not only on the resolve directory), applied the same way in bundled, unbundled, resolve-only and Bun-harness modes, but only when the pre-resolution path is under `node_modules/` or `.proscenium/packages/`. That makes one real file one module in every mode: under pnpm and Bun the app and a gem reach one shared package such as React through different link paths that end at the same file, and with symlinks preserved (`internal/builder/build.go:105`, `internal/builder/compile.go:125`, `internal/resolver/resolve.go:147`) an unbundled page could load it twice. An app's own `link:`, `file:` and workspace-sibling packages keep today's paths; a regression for each (the `fixtures/dummy` cases) lands before any Stage C change. The real-path normalization at `bundless.go:80` also runs for resolves from a context directory.

Dependency URLs stay real-path through `UrlPathFromFsPath` (fed by the resolve-dir EvalSymlinks at `bundless.go:80-81`), so a pnpm or Bun app's unbundled URLs keep their `.pnpm` and `.bun` store segments as today; distinct peer variants get distinct real paths. Wherever a linker can nest a conflicting version under a context, the copy's real path is under `.proscenium/packages/<gem>/node_modules/`, so the serving allow-list (`ALLOWED_DIRECTORIES`) and the URL mapping cover that path with the same containment rules as `node_modules`. Stage A records whether Bun's hoisted linker nests. A typical dotfile-deny proxy rule in front of Rails would block `/.proscenium/...` and `/node_modules/.pnpm/...` URLs; the deployment notes cover it. (Stage C: documented, with no test of its own. A test would exercise a proxy's configuration, not Proscenium, and the two URL prefixes such a rule must allow are already pinned by the context Go specs and the middleware test.) A URL scheme independent of the manager is tracked separately (TODOS.md).

Preserve `/node_modules/@rubygems/<gem>/...` URLs, manifest lookup keys, CSS module identity, `__filename`/`__dirname` virtual identity, fonts and images, dynamic import chunks, source maps, aliases, SVG handling, frontend replacements, Rails side-loading from installed gem paths, and bundled/unbundled behavior. No gem-to-copy or reverse-copy mapping is needed.

### Mapping generations

Every request or build uses one immutable mapping generation. In production a generation lives for the process (restart after deploy). In development the engine checks, at most once per second per process, the modification times of Gemfile.lock, `proscenium.json`, `.proscenium/packages/*/package.json`, participating gems' package.json, path gems' gemspec files (participation metadata), the root workspace registration (package.json `workspaces`, pnpm-workspace.yaml) and the linker configuration (`.npmrc`, `bunfig.toml`), plus the disappearance of `.proscenium/installing`. On a change it rebuilds the map and invalidates the `BundledGems` and resolver caches; the Bun daemon's build cache key includes the generation. The memoized `BundledGems` state is rebuilt while requests run, so this path has a thread-safety test under Puma. The generation is not keyed on the whole native lockfile: an ordinary `pnpm add left-pad` changes the lock without touching any context and must not force an install.

When the engine builds a generation it repeats the peer-sharing check (a Ruby real-path comparison), so an app-only `pnpm update react` that splits a shared peer is reported at the next build. Frontend-only path-gem edits keep the current development asset behavior; a dependency-manifest edit needs `install`.

## Cross platform and deployment behavior

Separate platform-independent dependency metadata from host-specific native installations. Context paths are project-relative and case-safe; installed gem roots remain local runtime mappings supplied by Bundler. Serialize portable paths with slash form and convert only at filesystem boundaries, following the repository's two-path-space convention. Frontend source bytes and executable modes remain as installed by Bundler, and Proscenium never transforms gem source line endings.

Windows must work without Proscenium-created source links or frontend copies. The native manager may need its own dependency links or junctions and must be qualified under ordinary-user conditions; CI enabling Git symlinks does not prove this. Test drive and UNC paths, spaces, reserved names, case collisions, long paths, and context replacement while processes run. The CLI's Windows behavior (`.cmd` shim resolution, Ctrl-C delivery to the manager, lock release when the CLI is killed) is qualified on windows-latest.

Locked platform variants of a gem must project equivalent dependency metadata and the same participation eligibility; differing declarations are unsupported until a profile-aware native-lock design is proven (C33). Frontend payloads may differ exactly as supplied by native gem variants and are served from the installed variant. Never commit installed absolute gem roots.

Native optional OS/CPU/libc packages are resolved and installed by the selected manager. Do not copy `node_modules` across OS, architecture or libc boundaries. Test a lock produced on macOS in Linux and Windows with each manager's platform policy. A platform graph difference that needs a lock rewrite is fixed through native tooling before freezing, never silently patched by Proscenium.

**Deployment sequence.** Provision pinned Ruby and JS tooling; restore compatible caches; `bundle install` with the project's deployment settings; `bundle exec proscenium install --frozen --production`; `assets:precompile`, which is the deploy-time drift gate because the engine's stale-context error fires there; an asset smoke check; then start Rails. A fixture covers Heroku-style buildpack order, both Node first and Ruby first. The guide includes a Dockerfile layering example. By default every committed context is installed in production, even for gems only in excluded groups; Stage A records per manager whether a production install can exclude them (`pnpm --filter`, Bun `--filter`), and the docs state the cost.

**CI.** The drift check is `bundle exec proscenium install --frozen`, run with every Ruby group installed. The CI recipe gives the post-upgrade command for Dependabot and Renovate gem bumps (`bundle exec proscenium install`, then commit `.proscenium/packages` and the lock), so the frozen check is never disabled to let a bot through.

The asset engine's platform list is unchanged: the CLI is plain Ruby, but the engine's C-shared/FFI library still does not load on musl, and supporting it there needs a separate loading-architecture investigation.

[Current platform build policy](https://github.com/joelmoss/proscenium/blob/b3c795745ceb6f4810d41283616dee61865834d9/AGENTS.md). [Bundler lockfile checksums and variant handling](https://bundler.io/blog/2024/12/19/bundler-v2-6.html).

## Security and failure recovery

Gemfile and gemspec evaluation, native extension builds, JS dependency scripts, manager plugins and configuration, and the manager executables are existing execution trust boundaries; delegation does not sandbox them. Proscenium's added manifest parser, context writer and process launcher introduce no implicit execution path.

Participation widens the app's JS install graph to whatever an opted-in gem's manifest declares, including dependency lifecycle scripts that run under the app's native script policy. The committed context diff in the pull request is the review point for that change, and each context says it is generated. Gem metadata never changes the app's script approvals: pnpm's build approval policy and Bun's `trustedDependencies` remain native application policy, and Bun registration requires an explicit `trustedDependencies` array so that Bun's default trusted list never applies to packages a gem introduces. Stage A verifies on each Bun line that an explicit array replaces the default list; if it does not, Bun registration is refused until another mechanism is proven. Stage A also includes a gem-introduced `github:` dependency with a `prepare` or `postinstall` script, which must not run without the app's approval on any line. Lifecycle equivalence between managers is never claimed, and `--ignore-scripts` does not block later task commands.

The registry boundary for gem identities has three layers: the dependency allow-list and `npm:` alias normalization before the manager runs, the post-install lock scan (exit 5 on any `@rubygems/*` registry tarball), and conformance fixtures run against a local request-logging registry, so "no public registry request, no `@rubygems/*` request" is asserted directly.

Preserve TLS, native authentication and checksum verification, lock checksums, private scopes, script approvals and patch policies. Never refresh failed checksums automatically. Bind each context to locked source identity and the projection hash. Mutable path-gem dependency declarations need `install` before a frozen deployment; frontend-only edits do not alter the JS graph.

Apply containment and race checks when reading manifests, reading archive metadata and writing owned state. Guard against traversal, unsafe symlink targets, archive expansion abuse, case collisions, oversized metadata and special files. Native Bundler installs gem payloads; Proscenium never extracts asset trees. Asset-serving authorization keeps using existing gem roots and file rules, with the one addition of nested copies under `.proscenium/packages/<gem>/node_modules/`; generating dependency metadata grants no other serving permission.

Logs and JSON exclude credentials, auth headers, tokenized source URLs, home-directory prefixes and private manifest values unrelated to diagnosis. Committed configuration and contexts contain no secrets. `inspect` distinguishes checksums from signatures or provenance authenticity. Auditing is delegated to each ecosystem's native tools.

Recovery: an interrupted install leaves `.proscenium/installing` and the engine refuses to build until a re-run completes; the lock passes to the manager child, so a retry cannot overlap a surviving installer; owned committed files are restored with Git. Native caches and installed Ruby gems can remain after a failure.

[Bun lifecycle and trust policy](https://bun.sh/docs/pm/lifecycle). [pnpm 10 build-script settings](https://github.com/pnpm/pnpm.io/blob/main/versioned_docs/version-10.x/settings.md).

## Performance strategy and measurable gates

Keep resolution delegated and reuse native caches and stores. Unchanged contexts are never rewritten, so native links and `node_modules` survive; the native manager alone manages dependency payloads and pruning. Source-only gem edits need no metadata regeneration. The CLI never loads Rails or esbuild. The engine never hashes a gem tree on a browser request: it parses participating manifests once per mapping generation (about 31 ms for 184 manifests) and checks file modification times at most once per second per process in development.

Proposed targets, not measured results: a warm no-op `bundle exec proscenium install` writes nothing and stays within 20% of the bare `pnpm install` or `bun install` on the same project. Report it split into Ruby boot, Bundler load, projection and native install time, with the process count. Proscenium-written frontend bytes MUST equal zero. Calibrate the budgets on pinned hosts before release (Stage D). The 100-gem performance gate is deferred (TODOS.md).

Benchmark a cold checkout, a warm cache with an empty `node_modules`, a no-op install, one changed path gem, one upgraded gem, a failed network and production omission. Use five measured repetitions after warm-up and report median and p95 with hardware, manager, Ruby and Node versions, lock hash, cache state and generated bytes. The local fixture timings are not product benchmarks.

## Adoption migration and rollback

The engine registry controller is unused, so it needs no compatibility obligation, deprecation period or rollback path. The real migration population is the three known consumers, and each is an acceptance case (C41). There is no migrate command in v1; the guide gives a written recipe instead:

- **codaset (Bun):** record its Bun version and raise it to at least 1.4.0; set `[install] linker` in bunfig.toml to the linker it uses today and add an explicit `trustedDependencies` array; opt proscenium-ui in; remove the `@rubygems/proscenium-ui` dependency from package.json and the `@rubygems` scope line from `.npmrc` in the same step; run `bundle exec proscenium install`; commit. The maintainer retires `registry.proscenium.rocks` afterwards.
- **platform and london (pnpm):** opt hue in; remove the `github:` pin for `@rubygems/hue`; run `bundle exec proscenium install`; commit.
- **All three:** check whether TypeScript, ESLint or a test runner relies on `node_modules/@rubygems/<gem>`; the guide gives the tsconfig `paths` recipe that replaces it.

The recipe's general steps: verify existing gem asset imports and installed source roots as the baseline; opt gems in; install and review the native lock diff against that baseline, failing the migration if unrelated declarations change or a full update happens; remove obsolete Proscenium registry entries only after confirming nothing else needs them, never replacing `.npmrc` or other credential files wholesale; run a fresh frozen install with Rails stopped plus the existing asset regressions and context import smoke tests; assert no frontend copies or installed-gem writes; then update bootstrap and CI instructions and stop relying on tracked fixture `node_modules`.

Gems that do not participate keep existing asset serving and app-level dependency lookup before and after adoption. Self-contained files need no JS install.

Replace the registry implementation in this feature: remove the controller, its engine routes, registry setup documentation and comments, and obsolete registry-specific dependency rationale. Convert its strict-JSON, unreadable-manifest, package-identity and deterministic-content tests into manifest-validation coverage. Retain the asset-serving RubyGems middleware: it is distinct from the registry. Review whether the `json` dependency bounds remain needed elsewhere before changing them. Publish the bridge as experimental until each adapter qualifies.

Rollback reverts the owned files with Git (the registration, the `.gitignore` lines, `.proscenium/packages` and the native lock) and reinstalls through the previous native workflow. Existing asset-only gem imports use the previous engine mapping. Registry-backed fixture locks are replaced during implementation, not restored as a supported mode. No published gem content or shared cache is modified.

## Conformance test matrix

Every fixture compares a native baseline, with an explicitly specified dependency-only consumer manifest, against a Proscenium project using a real installed gem with equivalent dependency declarations. Compare per-manager graphs, diagnostics, scripts, locks and dependency identity. Separately compare Proscenium asset behavior against the existing engine using the original installed gem files. Ordinary native importability of the gem is not the baseline.

The Gate column says which stage each row gates: **A** is the pilot (its rows are the pilot's GO subset), then **B** CLI, **C** engine, **D** qualification and **E** migration. A row split across stages names the part each stage gates. PR CI runs every row on one host; release-gate rows (clean and frozen install, imports, platform variants, no-registry behavior and failure recovery) run on every supported host and manager in Stage D. Unsupported combinations must fail before mutation.

| ID | Fixture | Required result | Gate |
|---|---|---|---|
| C01 | Gems that do not participate: a self-contained gem and an app-dependent gem | Existing in-place serving; no context or settings created; self-contained assets work and external imports use app dependencies. | C |
| C02 | Built gem ships JS + CSS + manifest + registry dependency, opted in | Fresh install with Rails stopped; frontend reads remain at installed gem paths; native dependencies resolve; zero Proscenium asset copies. | C |
| C03 | External, vendored, path, registry and Git gems | Same asset URLs; exact locked source identity; no installed gem writes. | C |
| C04 | Gem imports through Proscenium and context lookup | Existing gem asset imports work; the context avoids accidental hoisting; a resolution miss is a named error, not an external; contexts are not advertised as native gem packages. | A |
| C05 | Existing user workspaces, exclusions and duplicate package names; a Rails app nested in an enclosing JS workspace | Existing packages unchanged; collision errors before native writes; the nested layout gets the unsupported-configuration error. | B |
| C06 | pnpm 11 and 12 with pnpm-workspace.yaml absent, present and stale; settings kept in `package.json#pnpm` | Correct workspace enumeration; YAML remains authoritative; no policy overwrite; `package.json#pnpm` settings read the same after the YAML is created (pnpm 11 and 12 no longer read that field at all, YAML or not, and warn that its keys were ignored, so this holds trivially). | B |
| C07 | `pnpm-lock.yaml`, `bun.lock`, `bun.lockb` only, `yarn.lock`, `package-lock.json`, `npm-shrinkwrap.json`, conflicting signals | Correct manager selection; no format conversion; Yarn and npm projects get the unsupported-manager error and `bun.lockb` only gets the unsupported-configuration error, before any write. | B |
| C08 | Repeated frozen install on unchanged inputs | Success; contexts, native locks and any receipt byte-identical. | A |
| C09 | Changed dependency manifest; an edited context with a stale lock; a stale or missing receipt if one is kept | `install --frozen` fails before the manager runs, on each manager line (Bun exits 0 when contexts are missing, so the CLI's own check is asserted); no lock repair or registry fallback. | B |
| C10 | Version ranges, prereleases, dist-tags, `npm:` aliases, Git URLs, tarballs | Native per-manager baseline semantics; Ruby and JS versions independent. | D  Stage D (2026-10-04) on Linux, macOS and Windows, pnpm and Bun: a gem declaring a range, a prerelease, a dist-tag, an `npm:` alias, a GitHub reference and a tarball URL gets each installed from its context into the same directory that a native workspace package declaring the same dependencies reaches, in one install. The context carries no `version`, so the Ruby and JS versions stay independent. |
| C11 | Conflicting transitive versions across two gems | Distinct native contexts retained; no flattening. | D  Qualified in Stage D (2026-10-04) on Linux, macOS and Windows, pnpm and Bun: two gems pinning ms 2.0.0 and 2.1.3 each keep their own in their context. |
| C12 | Present, missing and incompatible React peer and optional peer metadata, asserted through Proscenium's resolver bundled and unbundled; the app pinned at a non-latest in-range version, then bumped after the first lock; copies of london's, platform's and codaset's real configs with `auto-install-peers=false` and `resolve-peers-from-workspace-root=false` variants | Native peer policy matches the baseline; one React instance where the app declares React; a split after the bump is reported by `install` and at the next build. If no native setting makes the context share the app's copy, that is NO-GO. | A |
| C13 | Two contexts with different peer providers | Placement matches the native baseline; distinct variants have distinct real paths, each resolving its peer to its own provider. | A |
| C14 | Optional dependency fails build or fetch, or is omitted | Native optional behavior; non-optional failures remain failures. | D  Stage D (2026-10-04) on Linux, macOS and Windows, pnpm and Bun: an optional dependency that cannot be fetched is left out of the context, as natively. The same dependency, required, fails the install with PSM-E-NATIVE (exit 6). An optional dependency whose build fails is not exercised. |
| C15 | OS/CPU/libc packages; a lock created on another host | Native compatible variants installed; frozen inputs unchanged; incompatible host diagnosed. | D  Stage D (2026-10-04) on Linux, macOS and Windows, pnpm and Bun: fsevents, which runs only on macOS, is installed in the context and in the native package on macOS and left out of both elsewhere. A lock created on another host is not exercised separately. |
| C16 | engines, engineStrict, overrides/resolutions, patches/catalogs | Root policy preserved; a gem cannot promote its own policy. | D  Stage D (2026-10-04) on Linux, macOS and Windows, pnpm and Bun: an app-wide override of ms (in pnpm-workspace.yaml for pnpm, package.json for Bun) replaces both widgets' own pins. A gem cannot promote its own policy: the projection drops its overrides, resolutions, pnpm settings, patchedDependencies and engineStrict, and keeps its engines range as information only. A gem's `catalog:` specs are refused (PSM-E-SPEC). |
| C17 | Gem devDependencies and app devDependencies | Gem dev tools absent; app development and production omission match the baseline. | C |
| C18 | Install hooks, prepare hooks, `binding.gyp` in a gem | Author-contract error before execution, printing the consumer escape; native dependency scripts follow native policy. | B |
| C19 | pnpm build approvals, Bun `trustedDependencies`, ignore-scripts | Executed markers match native behavior; no auto-approval from gem metadata. | D  Stage D (2026-10-04): a gem's own approvals (`trustedDependencies`, `allowBuilds`, pnpm's `onlyBuiltDependencies`) are dropped from its context and leave its hash unchanged. Stage A's Git-scripts test shows that a gem-introduced dependency's scripts do not run without the app's approval, and do run once the app approves the package, on pnpm and Bun. |
| C20 | exports/imports, type, ESM/CJS, module/browser/main, sideEffects, self-reference, bin | Each dropped field behaves as classified (preserved by the engine reading the original package.json, or an author-contract restriction); existing gem and self-reference behavior preserved. | C |
| C21 | CSS @import/url, CSS modules, fonts, SVG, TS types | Original gem files resolve in place; stable class identity and URL ownership; a nested copy's font URL loads. | C |
| C22 | Bundled/unbundled code, dynamic chunks, aliases and import maps | Existing outputs preserved; a nested copy's chunk URL loads; missing and external behavior explicit. | C |
| C23 | Source maps, metafiles, manifest precompile, Rails side-loading | Original installed-gem source identity and virtual mapping preserved. | C |
| C24 | Bun runtime harness plus the new installer graph | App and gem imports and CSS module identity correct; harness chunk caveats retained; cached results refused while an install is in progress. | C |
| C25 | Yarn project in any mode | Unsupported-manager error (exit 3) before any write; no config or lock change. | B |
| C26 | Contained and escaped `file:`/`link:` references; cross-gem references with and without the gemspec dependency, to a target that participates and one that does not | Rejected references fail clearly with the consumer escape printed; backed references to a participating target rewrite to `workspace:*`; a non-participating target gets its own error. | C |
| C27 | Unicode, spaces, case collisions, UNC, drive, reserved names, long paths; a gem name with uppercase letters | Valid paths work; unsafe or colliding paths fail deterministically; the uppercase gem name gets a participation error naming it. | D  Stage D (2026-10-04): the install suite passes on Linux, macOS and Windows from an app directory named "app ü long-path-...", 120 characters longer than needed. On Windows that passes the old 260-character limit. Gem names that one host cannot hold (Windows device names, package names over 214 characters) are refused on every host. Uppercase is refused too, so two contexts never differ only in case. A project on a UNC path with a `.cmd`/`.bat` manager shim is refused (PSM-E-UNC-SHIM), since cmd.exe falls back to C:\Windows there; map a drive or use a native executable. |
| C28 | Read-only shared gem install and ordinary-user Windows | Contexts generate without gem writes, source mirrors or privileged links. | D  Stage D (2026-10-04): with the gems installed read-only, an install changes no file under the bundle path, checked against a seeded write, on all three hosts. Proscenium creates no links itself, so it needs no link privilege. Ordinary-user Windows: CI creates a standard user, turns Developer Mode off, and runs the whole install suite as that user, pnpm and Bun, from its own profile; the launcher first shows the user is outside Administrators (`whoami /groups`) and cannot create a symbolic link. 26 runs pass; the 2 skips are the C29 linked-path tests, which need a symbolic link to set up and run in the administrator leg. |
| C29 | Manifest and archive-metadata traversal, symlink races and special files | Safe reads and writes; no writes outside owned state; existing asset security tests retained. | D  Stage D (2026-10-04): a gem's package.json is read only if it is a regular file, inside the gem once links are followed, and at most 1 MB. A built gem's manifest entry is read only if it is a regular file within that limit, and nothing is extracted. Install refuses a linked .proscenium path (PSM-E-OWNED-LINK) before writing. |
| C30 | Tampered native package, gem archive or manifest | Native integrity verification retained; projection mismatches fail; no claim that a context authenticates asset bytes. | D  Stage D (2026-10-04) on Linux, macOS and Windows: with a lock whose recorded integrity for ms is tampered with and a cold cache, pnpm refuses the frozen install (exit 6) on every host. Bun refuses on Linux and macOS, but measured on Windows (and with a warm cache everywhere) it installs anyway, natively too, so Proscenium is held to Bun's own native verdict on the same tree. A hand-edited context fails `--frozen` (C09). A context does not authenticate asset bytes. |
| C31 | Private registries, proxies and credential-bearing URLs | Native auth works; no credentials in logs or contexts; no Proscenium registry requests. | D  Stage D (2026-10-04) on Linux, macOS and Windows, pnpm and Bun: a gem depending on a package from a token-protected registry installs with the app's own `.npmrc`. Every request carries the token, none asks for a gem, and the token appears in no output, context or lock. A gem dependency URL with a password in it is refused (PSM-E-CREDENTIAL). Proxies are not exercised. |
| C32 | Excluded Ruby groups with a committed context for an excluded gem; a non-host platform variant; unavailable locked sources | The engine never raises for the excluded gem's context; `install --frozen --production` and `--offline` trust committed contexts, report the skips and make no network request. | B |
| C33 | Platform variants with differing manifests or differing participation | Differences rejected; equivalent metadata passes; assets served from the installed variant. | D  Stage D (2026-10-04): when the Bundler cache holds a participating gem's other platform variants, `install` compares each with the installed one and refuses any that differs in participation or in its projected dependencies (PSM-E-PLATFORM-VARIANT, exit 3) before writing. Other fields and frontend files may differ; assets are served from the installed variant. |
| C34 | Interruption at each install step, with warm build and Bun-daemon caches | `.proscenium/installing` remains; the engine refuses to build or return a cached result and prints the re-run command; re-running `install` recovers. | B |
| C35 | Concurrent installs, a native command and editor changes; the CLI killed with SIGKILL while the manager runs | Second install exits 7; after SIGKILL an immediate retry exits 7 until the manager exits; user edits never overwritten. | B |
| C36 | Changed path gem, branch switch, gem upgrade or removal, a gem that leaves the bundle, drops its manifest or withdraws participation | Asset-only edits need no install; manifest changes make the context stale; `install` removes orphaned contexts and their lock entries in the same run; `install --frozen` fails on an orphan. | C |
| C37 | The installed CLI from the platform and plain archives, and from Git and path sources | `exe/proscenium --version` runs in a clean process with ActiveSupport, Rails, FFI and `Proscenium::Builder` not loaded; the plain archive still has no `lib/proscenium/ext/` entry; nothing compiled or downloaded. | B |
| C38 | Native targeted update commands | Deferred with the `update` command (TODOS.md). | Deferred |
| C39 | Existing gem asset app adopts the bridge and rolls back; obsolete registry removed | Unaffected declarations unchanged; legacy asset behavior recoverable; registry endpoint and documentation absent. | E |
| C40 | Warm and cold install, no-op, one gem change | Ruby boot, Bundler load, projection and native install time measured separately; within the calibrated target of the bare native install; zero frontend-copy bytes. | D  Stage D (2026-10-04) on Linux, macOS and Windows, pnpm 11 and 12 and Bun, Ruby 3.4 and 4.0: `install` reports each phase's time (load, manager check, bundle, projection, manager, verify). The test times Proscenium's own share, everything but the manager's run, for three installs: a cold first install with an empty manager store, a no-op frozen install, and an install after one gem changed (its context missing, as when it joins the bundle, and asserted reinstalled). Measured in CI: Linux 177 to 243 ms, macOS 166 to 331 ms, Windows 368 to 554 ms, about the same in all three cases. The ceiling is 2000 ms, set from the first no-op measurements. A context holds only its package.json: zero frontend-copy bytes. |
| C41 | Real consumers: codaset (Bun, proscenium-ui), platform and london (pnpm, hue) | Fresh checkout installs with no hosted registry and no `github:` pin for a gem; each gem pinned only in Gemfile.lock; existing imports and side-loaded assets unchanged. | E |
| C42 | Gem whose package.json lacks `version`, has a Ruby-style prerelease, or differs from the gem version (hue, proscenium-ui) | Context generated without `version` and linked with `workspace:*` on every supported line; no participation error; no registry request. | A |
| C43 | Gem declaring `react`/`react-dom` as `dependencies` instead of peers (hue) | Native result recorded per manager; one React instance in the app, or the author-contract diagnostic naming the fix. | A |
| C44 | Gem manifest referencing another gem's context by semver range, as a dependency and as a peer, with and without the gemspec dependency, with the target absent from the bundle | With the gemspec dependency and a participating target: rewritten to `workspace:*`, and a locked version outside the gemspec constraint fails in Bundler first. Otherwise: a participation error naming both gems, nothing rewritten. As an optional peer: linked when the target participates, omitted otherwise. No `@rubygems/*` registry request. | C |
| C45 | Native commands used directly: plain and frozen `pnpm install` and `bun install` on a fresh checkout, `pnpm add <pkg>` in a set-up project, a Gemfile change followed only by a native install | A: a fresh checkout installs every gem's dependencies with no lockfile change, and an app-only native command leaves contexts valid. B: after the Gemfile change, `install --frozen` fails (exit 4). C: the engine reports which gem is stale. | A, B, C |
| C46 | Same app installed by pnpm and by Bun, with an app/gem version conflict and a gem-only dependency | Gem imports resolve the gem's version and app imports the app's, on both managers. | A |
| C47 | App code importing a package only a gem declares | Result recorded per linker (it can resolve by hoisting under Bun's hoisted linker); the guide documents it. No CLI report in v1. | D  Stage D (2026-10-04) on Linux, macOS and Windows: a package only a gem declares does not reach the app's own node_modules on pnpm or under Bun's isolated linker; it does under Bun's hoisted linker. The consumer guide's "Import only what your app declares" documents it. |
| C48 | First run: fresh `rails new`, add Proscenium and one opted-in gem, import its component, follow the documented commands; also a project with no package.json or manager | The page renders after three commands (`bundle add`, `bundle install`, `bundle exec proscenium install`); the success summary matches; wall time on warm caches recorded against the 2-5 minute target; the no-manager case names `--manager`. | D  Stage D (2026-10-04, maintainer decision): a fresh `rails new -j bun` app sets no Bun linker and no trustedDependencies. `install` now writes the linker the app uses today (from its node_modules, or what Bun would pick) with the registration diff; `--frozen` still refuses without one. trustedDependencies stays the app's to declare, so the first run stops once at PSM-E-BUN-TRUSTED: four steps, not three. Measured: `rails new -j bun` 12.5 s, `bundle install` 1.7 s, `proscenium install` 0.4 s, then the gem's component builds. With no package.json the error names `--manager`. |
| C49 | Path gem inside the app tree whose context pins a version conflicting with the app's | The gem resolves its own version through the context, never the app's `node_modules`. | C |
| C50 | `actiontext` bundled without opting in; an opted-in gem with an invalid manifest; an opted-in gem with no manifest; consumer opt-in and opt-out | No actiontext context and no extra packages; both opted-in failures are participation errors; overrides behave as specified. | B |
| C51 | Bun app with no explicit linker, with each explicit linker, and with and without `trustedDependencies`; a gem introducing a package on Bun's default trusted list; a copy of codaset's real `bun.lock`, bunfig.toml and `.npmrc` | Registration refused without both settings; with them the layout matches the chosen linker and no `.old_modules-*` switch happens unannounced; the default trusted list never runs a gem-introduced package's script; codaset's unbundled pages and `bun test` harness still pass after registration. | A |
| C52 | Upgrade Proscenium on an un-adopted pnpm app with an opted-in gem, and on a Yarn app; an adopted app with zero contexts; removing the last participating gem | Both un-adopted apps still build and log the notice; adoption persists through a fresh clone. | C |
| C53 | `install` from a subdirectory and with `BUNDLE_GEMFILE` naming another app; a lifecycle script running `ruby -e`; manager `.cmd` shims and Ctrl-C on Windows | Contexts written only for the active bundle's `Bundler.root`; lifecycle environment identical to a direct native install; Windows cases pass. | B (Windows in D)  Qualified on windows-latest in Stage D (2026-10-04): a `.cmd` shim passes every argument `install` builds intact through cmd.exe; a real console Ctrl-C stops the manager and the install exits 8, even when the manager exits 0; a killed install's still-running manager keeps the next install out (exit 7) through `.proscenium/manager`. Ctrl-Break ends the CLI outright, since Ruby has no SIGBREAK. |
| C54 | Heroku-style buildpack order (Node first, Ruby first); `assets:precompile` with a stale context; a dotfile-deny proxy rule | Both orders install when the documented command runs after both; precompile fails on the stale context; the documented proxy rule serves `.pnpm` and `.proscenium` URLs. | D  Stage D (2026-10-04) on Linux, macOS and Windows, pnpm: the adopted app installs with Node first (`pnpm install --frozen-lockfile` before `bundle install`), then passes `proscenium install --frozen`. `assets:precompile` refuses a stale context (C23's test). The consumer guide's Deploying section gives an nginx rule that lets pnpm's store (`/node_modules/.pnpm/`), Bun's isolated store (`/node_modules/.bun/`, which the first draft missed) and a context's nested copies (`/.proscenium/packages/`) through a dotfile deny. A test runs that rule, read from the guide verbatim, in real nginx on Linux. Those paths reach the app and `/.env` stays denied; without the rule, the deny blocks them, which is the control. |
| C55 | Dependency specs on and off the allow-list; an `npm:` alias targeting `@rubygems/*`; a lock with an `@rubygems/*` registry tarball; a gem-introduced `github:` dependency with a `prepare` or `postinstall` script; a pnpm `minimumReleaseAge` failure | Allowed specs pass and are listed in the summary; the others fail with the consumer escape; the alias fails before the manager runs and the request log shows no registry hit; the lock scan exits 5; the Git dependency's script does not run without app approval (recorded in A); the age-gate failure names the gem context. | B |

Test layers: Ruby tests for the CLI with their own helper that loads no Rails; golden-output tests for every error code and exit status; Ruby tests for the projection and hash against shared golden vectors; real-manager graph, lock and script fixtures; Go tests for engine lookup and identity; Rails and Bun end-to-end imports from original gem sources. Fixtures are hermetic: proscenium-ui, the hue-shape `github:` dependencies and React come from committed tarballs and a local bare Git repository (`file://`), served by a seeded request-logging registry, and the read-only Bundler path is made writable again before cleanup (Windows). Every "nothing happened" assertion has a seeded positive control that must turn it red: an unrewritten `*` context reference for the no-registry check, a copied file for zero frontend writes, a write into a gem root, a boot-time Go call, an app-root fallback for context-only lookup, and `require 'proscenium'` for the CLI's load isolation. Before any Stage C change, regressions land for the app's `link:`, `file:` and workspace-sibling packages, and for the nested-gem-root and prefix-match cases fixed in `683dc375` and `c9cb03c8`, applied to context routing.

## Implementation sequence and release gates

**Stage A: the pilot.** Prove dependency-only contexts with real installed gems on pnpm and Bun before any CLI or engine work. Entry gate, owned by the maintainer: `bin/check-154-plan` passes on this document. The GO subset is every conformance row whose Gate includes A. A failing adapter stays unsupported; copied frontend trees are never a fallback. The consumer quickstart and the gem author guide are drafted at the end of Stage A and exercised against its fixtures. Re-estimating the remaining effort is a gate before Stage B. The execution contract is below.

**Stage B: the Ruby CLI.** `exe/proscenium` and its gemspec declaration; `install`, `install --frozen`, `inspect` and `gem check`; manager selection and the capability table; registration; the project lock and the install marker; the manager runner; validation; errors, exit codes and golden outputs; release verification of the installed CLI. Gate: rows whose Gate includes B. No Rails, FFI or engine loading by any command.

**Stage C: engine integration.** Connect participating gems to their contexts at the existing Ruby/Go lookup boundary: the context map in both config sites, the one lookup across every resolve path, real-path identity, nested-copy serving, adoption, staleness, the install-in-progress refusal and mapping generations. Preserve existing source roots, relative imports, serving middleware, URLs, source maps, manifest and side-load behavior, and Bun harness semantics. Gate: rows whose Gate includes C, plus the relevant existing asset suites and the regressions listed under the matrix.

**Stage D: qualification.** Run release-gate rows on every supported host and manager line, Windows and Linux included; qualify Ruby 4.0; set up the nightly canary; calibrate performance budgets. Gate: rows whose Gate includes D. An unqualified adapter remains an explicit error even if the other ships. Progress (2026-10-04): the whole suite runs on Ruby 4.0 on Linux, macOS and Windows; PR CI runs each manager line's floor (pnpm 12 on one Linux leg), and `canary.yml` runs each line's newest patch nightly on all three hosts; C40's ceiling holds for the cold, no-op and one-gem-changed installs; a standard Windows user runs the install suite (C28).

**Stage E: migration and release.** Replace registry-backed repository fixtures with clean installs; remove the unused registry feature and its setup instructions; migrate codaset, platform and london (C41), moving platform and london from pnpm 10 to 11 first (approving their build scripts and allowing their Git dependencies, which pnpm 11 refuses by default); add a "JavaScript dependencies from gems" section to the README after "Import from NPM", covering the one-command flow, what gets committed, the frozen CI step and a link to the gem author guide, and replacing any registry setup text; publish the quickstart, the gem author guide (one checklist whose executable form is `gem check`, an example package.json with React as a peer, a first-run transcript, a sample context file, a sample pull-request diff, a Dockerfile layering example, a CI recipe and the `bin/setup` line) and the compatibility evidence. Gate: rows whose Gate includes E. The maintainer retires `registry.proscenium.rocks` after codaset migrates. The stable label waits until a gem outside the maintainer's apps adopts the bridge.

Track stages as milestones on #154; split implementation child issues after Stage A settles the representation.

### Stage A execution contract

Implement a disposable proof under `test/package_manager/stage_a/` and publish commands, tool versions, fixture manifests, normalized graph captures, lock hashes and per-manager verdicts in `docs/plans/154-package-manager-stage-a.md`. The proof hand-writes contexts and may use a test-only resolver seam to route **external dependencies** from an original installed-gem issuer to its context. It must exercise existing source reads, relative and CSS resolution, and `@rubygems` URLs. It is a proof for Stage C, not a production CLI or resolver. No proof may copy assets or write installed gem roots.

Order:

1. **london, pnpm.** Hand-write `.proscenium/packages/hue/package.json`, register it, run pnpm, and route hue's bare imports through the context with the seam. Run it with `stage_a_hue_shape` in CI and confirm it locally against hue.
2. **codaset, Bun 1.4 or newer.** The first Bun probe repeats the linker measurement on a copy of codaset's real `bun.lock`, bunfig.toml and `.npmrc`, then re-runs codaset's unbundled pages and the `bun test` harness after registration (C51). Verify on each Bun line that an explicit `trustedDependencies` array replaces Bun's default list. Record whether the hoisted linker nests conflicting copies under a context.

Across both:

- The first peer probe pins the app at a non-latest in-range version (for example react 18.2.0 against a `^18.0.0` peer) on every pnpm and Bun line and records whether any native setting makes the context share it (C12). It runs against copies of london's, platform's and codaset's real JS configuration (locally, like the hue leg; public fixtures reproduce the relevant settings), with `auto-install-peers=false` and `resolve-peers-from-workspace-root=false` variants, and with the context both referenced from the app and unreferenced.
- An unbundled identity probe shows two link paths to one React file loading as one module in the browser, not only a bundled `===` check.
- A gem-introduced `github:` dependency with a `prepare` or `postinstall` script must not run without app approval on either line.
- Record per manager whether a production install can exclude contexts of gems only in excluded groups.
- Record whether london, platform or codaset use a Rails app nested in an enclosing JS workspace, and the hosts each app develops and deploys on.
- Decide whether a descriptor receipt is needed, by demonstrating each drift case one at a time.

Fixtures, all genuinely Bundler-installed into a temporary `BUNDLE_PATH` and then made read-only:

- Synthetic `.gem` archives built locally: the existing gem_npm fixture (string-length ^6.0.0), a self-contained `stage_a_assets` gem without package.json, and `stage_a_widget_a`/`stage_a_widget_b` at 1.0.0, which declare React ^18.3.1 peers and ms 2.0.0 / 2.1.3 respectively (not is-number, which the engine replaces with a browser-native module before any resolution); the app supplies React and react-dom 18.3.1. Manifests and frontend files are listed explicitly in each fixture's `spec.files`, and each sets `proscenium.dependencies`. Incompatible, optional and separate-provider peer variants are baseline comparisons.
- proscenium-ui, a real public Git-source gem at a pinned revision (manifest version behind the gem version, `github:` dependency), served from the hermetic fixtures in CI.
- `stage_a_hue_shape`, a public synthetic gem that reproduces hue's awkward traits exactly: no manifest `version`, `react` and `react-dom` as plain `dependencies`, a `github:` dependency, and package.json missing from `spec.files` (installed as a Git source so the manifest is still on disk). The CI fixture for C42 and C43.
- hue itself, run **locally only**. `harleytherapy/hue` is a private repository, so its source cannot be committed here and public CI cannot fetch it. The maintainer runs the hue leg against a local checkout at a pinned revision, and `docs/plans/154-package-manager-stage-a.md` records only the revision, tool versions, commands and verdicts, never hue's source or manifest contents. The maintainer re-runs the hue leg at each stage gate; if it and `stage_a_hue_shape` diverge, fix the synthetic gem.

Proof matrix: macOS ARM64, Node 22 and Node 26, Ruby 3.4.8, Go 1.25.7 with `GOWORK=off` for the engine seam, and Bundler selected by the repository's Ruby lock. Test the pnpm lines london and platform use plus the CI floor, and Bun 1.4.x at its newest patch plus 1.4.0. Record every runtime version. Other hosts remain unqualified until Stage D. Stage A asserts only what its rows' Gate A parts require; CLI diagnostics and ordinary-user Windows gates are later stages, not fictitious Stage A passes.

For each representation, compare with a native consumer graph with identical projected declarations, root policy and seeded choices. Pass means identical normalized package identities and versions, dependency edges, peer providers, optional omission, script markers and success/error classes. Do not require equal physical trees or identical diagnostic prose. Repeated frozen runs must preserve each project's committed bytes. Bundle a joint app/gem probe through the seam and execute it: shared React exports must compare `===`, with one React module instance in that output. Compare missing, incompatible and distinct-provider peers against the native baseline rather than forcing every case to share. Prefer the dependency-only workspace representation when several candidates satisfy every invariant; never switch representation silently.

A candidate GO requires original source identity, distinct dependency contexts, correct peers, reproducible frozen locks and no asset copies or gem writes. Zero qualifying adapters is NO-GO: report the evidence and reopen the design without starting Stage B. A partial GO permits Stage B for that adapter only after maintainer sign-off recorded on #154; the other stays unsupported.

### Suggested repository changes

| Path | Proposed work |
|---|---|
| `exe/proscenium`, `proscenium.gemspec` | The CLI executable; declare `spec.bindir = 'exe'` and `spec.executables = ['proscenium']`. |
| `lib/proscenium/cli/` | Commands, manager selection, capability table, registration splice, lock, install marker, manager runner, validation, output and error codes. Requires nothing beyond `proscenium/bundled_gems`. |
| `lib/proscenium/bundled_gems.rb` | The one Bundler reader: locked names, participation, projection, `projectionSha256` and the context map beside `paths`. |
| `lib/proscenium/builder.rb`, `lib/proscenium/runtime/server.rb` | Pass the context map to Go; the daemon's cache key includes the mapping generation and respects the install marker. |
| `internal/types/types.go`, `internal/plugin/bundler.go`, `internal/plugin/bundless.go`, `internal/css/mixins.go`, `internal/resolver/resolve.go` | The context map config and the one issuer-aware lookup; real-path identity; named resolution misses. |
| `internal/utils/utils.go`, `lib/proscenium.rb` | Nested-copy serving under `.proscenium/packages/<gem>/node_modules/` with the existing containment rules. |
| `bin/verify-installed-gem` | Run the installed `exe/proscenium --version` in a clean process and assert load isolation. |
| `test/package_manager/` | Stage A proof, conformance fixtures, the CLI's own test helper and the hermetic registry. |
| `.github/workflows/main.yml`, fixture manifests and locks | Clean install; pinned manager matrix; no registry boot dependency. |
| Registry controller, routes and tests | Remove; convert valuable validation cases. |
| README and guides | The README section, quickstart, gem author guide and migration recipe. |
| `bin/check-154-plan` | The Stage A entry gate for this document. |

Effort: the earlier estimate of 9-15 engineer-weeks predates the pilot scope, the four-command surface and the Ruby CLI, so it no longer applies. Re-estimate after Stage A; that re-estimate is a gate before Stage B.

### Acceptance criteria

- [ ] Stage A records reproducible real-gem evidence (synthetic gems including `stage_a_hue_shape`, proscenium-ui in CI, hue locally) and GO/NO-GO results per manager, including peer placement and app/gem React identity.
- [x] Decision D1 (context version) is settled: omit `version`, reference contexts with `workspace:*`.
- [ ] The installed CLI runs from every platform gem, the plain gem and Git and path sources without loading Rails, FFI or the engine, and passes the frozen, offline, production, lock and interruption tests.
- [ ] Gem assets remain at Bundler-installed roots with zero Proscenium frontend copies, mirrors, installed-gem writes or privileged source links.
- [ ] Opted-in gems install native dependencies; every other gem keeps existing serving and app-context dependency lookup.
- [ ] Existing `@rubygems` imports, public URLs, CSS identities, source maps, side-loading, precompile behavior and Bun harness semantics pass regressions.
- [ ] Routine installs preserve user manifests; repeated frozen installs leave contexts and native locks byte-identical.
- [ ] Clean CI installs with Rails stopped and no scoped registry shim; unused registry code and instructions are removed.
- [ ] codaset, platform and london are migrated (C41) and `registry.proscenium.rocks` can be retired.
- [ ] `proscenium gem check` and the gem author guide ship, and `gem check` catches a manifest missing from `spec.files`.
- [ ] pnpm and Bun each pass their conformance rows on supported hosts; exact versions, unsupported managers and measured performance are documented.

### Related

- #82: existing registry refinement request; this plan replaces that feature.
- #137: registry findings, closed 2026-10-03 as superseded by this plan; preserve useful validation, identity and integrity coverage when removing the controller.
- #155: raised the repository's Bun and pnpm pins.
- TODOS.md, section "Package manager (#154)": the deferred work, with reasons.
- `bin/check-154-plan`: the Stage A entry gate for this document.

## Research limits and settled decisions

Official manager, RubyGems/Bundler, Node and esbuild documentation was checked on the research date. Version-sensitive facts are qualified against repository pins. The earlier local probes used complete local workspace packages, not dependency-only descriptors, real installed-gem lookup or registry packages; the review probes were scratch measurements. No bridge implementation, engine build, integration suite, Windows or Linux run, Plug'n'Play prototype or real peer-context migration was completed, and no CLI or revised gem was built or benchmarked. The asset-serving requirement is settled; the native dependency representation remains a hypothesis until Stage A.

Highest-risk open questions: native peer and root attachment for dependency-only contexts, directing the engine's external dependency lookup without changing source-local semantics, and Bun's linker behavior on real apps. Stage A must prove these against real gems and existing engine behavior. If a representation fails, investigate another metadata-only native mechanism or leave that adapter unsupported. Do not recover by copying frontend assets, flattening dependency declarations, inventing a registry or replacing native resolvers.

No decisions are open. Settled, with the reasoning for each in the Review record below:

- **D1: a dependency context's version.** The generated context omits `version`, and every reference Proscenium generates to it uses `workspace:*`. A gem author's range for another gem's context is rewritten the same way, but only when the other gem is a runtime dependency in the referencing gem's gemspec and participates ([References between gems](#references-between-gems)). Bundler has already selected the gem version, so a JS-side version adds nothing and would be a second pin that can drift. Rejected: requiring authors to maintain `version` (rejects hue today, adds a drifting pin), and copying the Gemfile.lock version (Ruby prerelease syntax breaks pnpm 10 and 11). Evidence: [Version probes](#version-probes-3-october-2026).
- **Context metadata is committed**, not ignored, so native commands are safe to use directly ([Fresh-checkout probes](#fresh-checkout-probes-3-october-2026)).
- **Support rule:** owner-maintained release lines only, narrowed in v1 to the lines the pilot apps run plus a CI floor ([Compatibility](#compatibility)).
- **v1 is a pnpm and Bun pilot** with a kill criterion and no time box. npm and Yarn are unsupported; each would be a later adapter with its own evidence.
- **Four commands:** `install`, `install --frozen`, `inspect` and `gem check`. Everything else is deferred until a user needs it.
- **Dependency URLs stay real-path.** A manager-independent URL scheme is separate work.
- **Participation is opt-in**, by the gem author's gemspec metadata or the app's `proscenium.json`, because Rails' own gems ship manifests.
- **The CLI is Ruby**, run under `bundle exec`, because the bundle is already loaded there and a compiled CLI would add a second Ruby boot, five binaries and a cross-language protocol for no measured gain.
- **No context name override in v1.**
- **A stale context is a build error after adoption**, with `PROSCENIUM_STALE_CONTEXT=warn` as the incident escape.
- **Each gem keeps its own context**; gem dependencies are never flattened into one.
- **The hosted registry is retired** at the maintainer's discretion after codaset migrates, so there is no deadline driving a stopgap.

## Review record

### Autoplan run 2026-10-03 (branch docs/154-plan-review)

Restore point: `~/.gstack/projects/joelmoss-proscenium/docs-154-plan-review-autoplan-restore-20261003-233014.md`. UI scope: no. The view-term hits (`component` x2, `form` x2, `layout` x6) are all non-UI senses (gem frontend components, "array/object form", dependency layout), so Phase 2 (design) is skipped. DX scope: yes (developer CLI; `scope --developer-tool`). Codex: ready. Prerequisite /office-hours offer skipped: the plan already states premises, verified assumptions and rejected alternatives.

#### CEO Step 0

Mode: SELECTIVE EXPANSION (autoplan override). The 0E file-count rule alone would recommend SCOPE REDUCTION (well over 15 planned changed files); that pressure is carried into the premise challenges below rather than into a mode change.

Pre-review audit. Clean tree on `docs/154-plan-review`, no stash entries. Recent churn is CSS parser work (#150) and docs; nothing in flight touches the registry, `bundled_gems.rb` or the resolver lookup this plan changes. TODOS.md has no #154 entry; its `@rubygems` items (#95, the alias/`..` containment notes) sit in the same `bundler.go`/`bundless.go` code Stage C edits. No design doc. Brain digests empty. Prior learning applied: gemspec-dependency-needs-upper-bound (confidence 10/10, 2026-10-02), relevant if the CLI or helper adds a runtime dependency.

Citations verified against code: `bundled_gems.rb:9` uses `Bundler.load.specs`; `bundler.go:311-325` routes a gem's bare imports to `node_modules/@rubygems/<gem>` (real path) when present, else the app root; `build.go:105`, `compile.go:125`, `resolve.go:147` set `PreserveSymlinks: true` for unbundled/resolve; `main.yml:191` comment matches. Corrections: (1) the architecture table says `fixtures/dummy/package.json` pins pnpm 10.4.0; it pins `pnpm@10.34.6` since #155. (2) `bundless.go:81` already evaluates symlinks for bare imports inside node_modules, and the dummy's `node_modules/react -> .pnpm/react@18.3.1/...`, so unbundled dependency URLs today already carry `.pnpm` store segments. The manager-independent URL scheme in "Asset resolver integration" is therefore new behavior that changes existing URLs, not preservation.

Landscape. Layer 1: Rails gems either dual-publish their JS to npm (turbo-rails/stimulus-rails pattern) or vendor prebuilt JS into the gem; npm_assets-style rake tasks that edit package.json are the old third way. Layer 2: no standard answer for gem-carried JS dependencies in 2026. Layer 3: the plan's move, gem as the only pin plus native workspaces, beats Layer 1 for gems whose JS must match the Ruby version and for private gems (hue) where npm publication is unwanted. The shared-React constraint is what separates it from vendoring. Bundler exposes an `after-install-all` plugin hook, which is an unconsidered trigger point.

0A Premise challenge.
- P1 (valid): gem-carried package.json as the dependency source, Gemfile.lock as the only pin. Real pain: codaset's hosted registry and the hue double pin that has drifted.
- P2 (challenged): the Go CLI orchestrator. Every install path runs the batched Ruby/Bundler helper (algorithm step 3), so Go's startup advantage never applies to install. Context metadata is committed and native commands work directly (C45), so the orchestrator's added value is "run bundle install, regenerate contexts, run the JS install". The parts that deliver the motivation are the context generator, workspace registration and the engine lookup change. The launcher, bootstrap, version handoff, journals, process lock and add/remove/update/migrate commands are most of the 9-15 weeks. The plan calls Go settled, so this is queued as a candidate User Challenge pending the outside voices.
- P3 (challenged): the manager-independent dependency URL scheme with peer digests. Real-path URLs (today's behavior) already give one URL per physical instance, and pnpm's peer-suffixed store paths already separate peer variants. Manager independence only matters when an app switches managers or the hoisting changes. Candidate User Challenge pending outside voices.
- P4 (sizing): 47 conformance rows across five hosts and seven manager lines for three known consumers, all the maintainer's. Kept; flagged for Eng.
- Do-nothing cost: the hosted registry stays up, hue keeps drifting in two apps, outside authors have no supported path.

0B Existing code leverage. `bundled_gems.rb` (Bundler authority, gem roots); `bundler.go:311` per-gem bare-import resolve dir (Stage C is a retarget of this branch from `node_modules/@rubygems/<gem>` to `.proscenium/packages/<gem>` with no app-root fallback for participating gems, not a new mechanism); `bundless.go:81` real-path resolution; `utils.UrlPathFromFsPath` (single fs-to-URL rule); registry controller strict JSON/identity validation (port into manifest validation); Rakefile `PLATFORMS` and `bin/verify-installed-gem` (extend for the CLI binary); `lib/proscenium/runtime/` Bun harness.

0C Dream state.
```
  CURRENT                         THIS PLAN                          12-MONTH IDEAL
  gem JS deps via hosted     -->  committed per-gem contexts,  -->   any Rails gem ships JS deps by
  registry or github: pins;       native npm/pnpm/Bun install,       adding package.json; apps run
  two pins drift; CI needs        Gemfile.lock only pin, engine      their own manager; Proscenium
  committed node_modules          resolves from context dir          only generates metadata and
                                                                     resolves; outside authors use it
```

0G Selective expansion. Hold checks: complexity is far past 8 files and 2 new services (P2/P4 above). Minimum change for the goal: generator + registration + Stage C retarget + migrate three apps. Delight scan:
1. Regenerate contexts automatically from a Bundler `after-install-all` plugin hook. Deferred (TODOS) behind the P2 challenge.
2. Author guide tells authors to run `proscenium gem check` before `gem build`/release. Accepted (S, docs only).
3. Stale-context warning from the engine in development. Already required (C45). No change.
4. `proscenium inspect --why <js-package>` naming which gem contexts pull a package. Deferred (TODOS, P4).
5. Gem upgrades show their JS dependency changes in the PR. Free with committed contexts. No change.

<!-- autoplan-baseline-edits:ceo {"sourceSha256":"f3ff894fc52d8db6d1449eee82e6cd496cbabd4baeee09c4659a948e82466b7f","replacements":[{"oldText":"| `fixtures/dummy/package.json` | Pins pnpm 10.4.0 and contains","newText":"| `fixtures/dummy/package.json` | Pins `pnpm@10.34.6` (raised by #155) and contains"},{"oldText":"Ignore (the generated ignore rule covers `.proscenium/*` except `.proscenium/packages/`);","newText":"Ignore (the generated ignore rule covers `.proscenium/*` except `.proscenium/packages/`, and also `.proscenium/packages/*/node_modules/`, which native managers create there);"},{"oldText":"(`.proscenium/packages/<gem>/`), with no fallback to the app root.","newText":"(`.proscenium/packages/<gem>/`), with no explicit retry against the app root. Ordinary node_modules walk-up from the context directory still applies; that walk-up is how npm's hoisted copies are found, and it is why `doctor` (C47) reports undeclared imports rather than the resolver blocking them."},{"oldText":"| C09 | Stale/missing descriptor receipt or changed dependency manifest |","newText":"| C09 | Changed dependency manifest, or a stale/missing descriptor receipt when Stage A retains the receipt |"},{"oldText":"#155 raises them to Bun 1.4.2 and pnpm 10.34.6","newText":"#155 raised them to Bun 1.4.2 and pnpm 10.34.6"}]} -->

<!-- autoplan-accepted:ceo -->
- "Asset resolver integration" states that unbundled dependency URLs today are real paths that include `.pnpm`/`.bun` store segments (`bundless.go:81`), so any manager-independent scheme changes existing URLs for pnpm and Bun apps.
- Stage C changes the two existing gem bare-import paths rather than adding a parallel mechanism. For a participating gem, a bare import resolves once, from `.proscenium/packages/<gem>`, and that resolve replaces the whole existing chain: the `node_modules/@rubygems/<gem>` branch in `internal/plugin/bundler.go:311-337`, and all three steps in `internal/plugin/bundless.go:384-417` (the unchanged resolve dir, the gem-root retry and the app-root retry). Step 1 is included because its walk-up from an in-tree path gem would reach the app root's `node_modules` before the context. Non-participating gems keep both chains unchanged. Verified by C04, C46 and a path gem inside the app tree whose context pins a version that conflicts with the app's.
- The real-path normalization in `bundless.go:80`, which today runs only when the resolve dir is inside `node_modules`, also runs for resolves from a context directory, so a context-resolved package gets the same real-path treatment as any other dependency (the identity scheme itself is still the Eng phase's choice).
- Participation is manifest-driven: a gem participates when its installed root (or `proscenium.frontend_root`) has a package.json and `gemOverrides` does not exclude it, and a participating gem requires a committed context. `gemOverrides.<gem>.participate: false` excludes a gem whose package.json is not meant for consumers (dev tooling); an excluded gem keeps today's app-context lookup and gets no context.
- The engine's only inputs are committed files and Bundler: the Ruby side builds the gem-to-context map at Rails boot from `Bundler.load.specs` (as `bundled_gems.rb` does), a directory listing of `.proscenium/packages/` and a stat of each gem root's package.json (no JSON parsing at boot), and passes it to Go in both config sites that carry `RubyGems` today: `lib/proscenium/builder.rb` and the Bun daemon's `lib/proscenium/runtime/server.rb:235`. The engine therefore works after a plain native install on a fresh checkout. `.proscenium/state.json`, `map.json` and the journal are CLI-only state; the engine reads none of them except that it refuses to build while a CLI journal marks an install in progress (C34). The "map.json" and step 8/9 text describing engine-read local state is superseded by this.
- Each generated context records its source manifest's SHA-256 in a top-level `"proscenium": {"sourceManifestSha256": "<hex>"}` field (byte-stable: it changes only when the gem's package.json bytes change). Staleness is checked in two places. Engine staleness, from the boot map: a participating gem with no committed context, a committed context for a gem absent from Gemfile.lock, or a participating gem whose installed package.json hash differs from its context's recorded hash (the boot map hashes those few files once per mapping generation). A context for a locked gem in a group excluded by `BUNDLE_WITHOUT` is not an orphan and never raises. Engine staleness is a build error in every environment, naming the gem and `bin/proscenium install`. Full projection staleness (also covering gemspec runtime dependency changes and the locked universe) is checked by `install --frozen` and `sync`, which regenerate each context from Ruby-helper inputs and compare bytes. The engine never computes projections. Erroring rather than warning is deliberate: a stale context silently resolves a gem's imports against the wrong dependency graph, and only apps that adopted the bridge can hit it. Verified by C45, C09 and C32 (excluded-group contexts do not raise).
- `.proscenium/packages/` is a directory Proscenium owns: every entry there is a generated context, and a user package placed there is a participation error. When a gem leaves the bundle or stops shipping package.json, `install` removes its context directory and then runs the native JS install so the lock is refreshed in the same run; `sync` never deletes a context and instead fails naming the orphan and `bin/proscenium install`; frozen mode fails (exit 4) on an orphan. Verified by a new C36 case.
- If Stage A drops the descriptor receipt, locked source identity is checked from Gemfile.lock alone, and every requirement that names the receipt (artifacts table, step 8, frozen-mode rules, `install --frozen`) applies only when the receipt is kept.
- Registration is the default: the app's package.json gets no dependency edge to a context. Stage A runs each manager line with the context referenced from the app and unreferenced, with each manager's default peer settings (including pnpm's `auto-install-peers`), and records whether an unreferenced context installs its dependencies and gets the app's React. An app edge is added only if Stage A shows it is required, as a one-time visible initialization edit.
- First initialization reports the `.gitignore` lines it adds (`.proscenium/*`, `!.proscenium/packages/`, `.proscenium/packages/*/node_modules/`) with the other owned edits.
- The gem author guide's release checklist tells authors to run `proscenium gem check` before building or releasing the gem.
- `proscenium gem check` reads `spec.files` through the batched Ruby helper (gemspec evaluation stays in Ruby); for a built `.gem` it reads the archive's metadata without unpacking frontend files. Verified by a gem whose package.json is missing from `spec.files` (hue's shape).
- The release qualification matrix (Stage D) includes Ruby 4.0, which the scope table lists; Stage A's Ruby 3.4.8 proof does not qualify it.
- The maintainer re-runs the local hue leg at each stage gate and updates `stage_a_hue_shape` when they diverge.
- Stage gates match the rows that verify them. Stage A gates only the representation parts: C45's native-command install results, C09's in-memory projection comparison through the prototype, and C46's version-resolution part through the resolver seam. The URL-identity part of C46 and the engine error part of C45 gate Stage C; the `install --frozen` parts of C09 and C45 gate Stage B. Stage C also gates C04, the new C36 orphan case and the in-tree path gem case; C47 gates Stage D.
- The conformance matrix gains the cases these requirements cite: C36 adds a gem that leaves the bundle or drops package.json; a new row covers a path gem inside the app tree whose context pins a version conflicting with the app's; C32 adds a committed context for an excluded-group gem.
- Stage E records codaset's Bun version and raises it to at least 1.4.0 before migrating it.
- The deployment and CI guide makes `bin/proscenium install --frozen` (or `proscenium sync --check` equivalent) a required step, and the plan states that a plain native install alone does not prove contexts match the locked gems.
- "Security and failure recovery" states that participation widens the app's JS install graph to whatever a gem's manifest declares, including dependency lifecycle scripts under the app's native script policy, and names the committed context diff in the pull request as the review point for that change.
- The plan adds a short "Why not publish gems' JS to npm" rationale: private gems such as hue, a second release channel that drifts from the gem version, and JS that must match the Ruby code in the same gem release.
- A Ruby helper protocol version mismatch (helper schema newer or older than the CLI expects) exits 3 naming both versions and the fix, never a parse error.
- Engine debug logging (`cfg.Debug`) records each bare import routed to a context, with the gem and the resolved path.
- Conformance fixtures install from local tarballs or an offline cache, never the public registry, and C27 includes a gem name with uppercase letters (invalid as an npm name without an override).
- Before Stage A starts, these accepted requirements are folded into the sections they amend and superseded text (engine-read `map.json`, steps 8-9) is removed, so the plan has one source of truth.
<!-- /autoplan-accepted:ceo -->


<!-- AUTONOMOUS DECISION LOG -->
## Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| 1 | CEO | Mode SELECTIVE EXPANSION | Mechanical | autoplan override | /autoplan fixes the CEO mode | SCOPE REDUCTION per file count |
| 2 | CEO | Skip /office-hours offer | Mechanical | P6 | Plan already holds premises and alternatives | Run office-hours |
| 3 | CEO | Correct pnpm pin claim in architecture table | Mechanical | P5 | Verified fact: `pnpm@10.34.6` | Leave stale |
| 4 | CEO | State that today's unbundled URLs carry `.pnpm` segments | Mechanical | P5 | Verified at `bundless.go:81` and the dummy's links | Leave "preserve" framing |
| 5 | CEO | Stage C retargets `bundler.go:311` branch | Mechanical | P4 | Existing per-gem resolve dir does the job | New lookup mechanism |
| 6 | CEO | Accept: guide tells authors to run `gem check` before release | Mechanical | P2 | Docs only, in blast radius | Skip |
| 7 | CEO | Defer: Bundler after-install-all hook regeneration | Taste | P3 | Depends on the P2 orchestrator challenge | Add now |
| 8 | CEO | Defer: `inspect --why` | Mechanical | P3 | New command outside the minimum | Add now |
| 9 | CEO | Queue P2 (Go orchestrator) and P3 (URL scheme) as candidate User Challenges | User Challenge (pending voices) | — | Both change settled user direction | Auto-decide |
| 10 | CEO | Spec review 1: add node_modules ignore, gem check via Ruby helper, staleness signal, orphan cleanup, app-edge default, Ruby 4.0 in Stage D, hue fidelity owner | Mechanical | P1 | Real gaps the reviewer found in both inputs; each is a clarification inside the user's direction | Leave gaps |
| 11 | CEO | Spec review 1: "no fallback" means no explicit app-root retry; walk-up stays | Mechanical | P5 | Contradiction with npm hoisting evidence and C47 | Keep ambiguous wording |
| 12 | CEO | Spec review 1: C09 conditional on Stage A keeping the receipt | Mechanical | P5 | Receipt is optional in the artifacts table | Keep unconditional |
| 13 | CEO | Spec review 1: real-path vs canonical identity choice | Taste (to Eng) | P3 | Implementation choice; Eng phase owns it | Decide in CEO |
| 14 | CEO | Spec review 1: doctor/C47 flagged as unapproved scope | Mechanical | P6 | Factual correction: C47 is in the user's own plan, not a CEO addition | Cut |
| 15 | CEO | Spec review 2: engine builds participation map at boot from Bundler + committed contexts | Mechanical | P5 | Fresh checkout after a native install had no map | Machine-local map only |
| 16 | CEO | Spec review 2: split staleness into structural (engine, build error) and projection (CLI only) | Mechanical | P5 | Engine has no gemspec/universe to recompute projections; one rule for every environment | Engine recomputes projections; dev-only warning |
| 17 | CEO | Spec review 2: participating gems resolve only from the context (whole chain replaced) | Mechanical | P1 | Step 1 walk-up hit the app root first for in-tree path gems | Replace steps 2-3 only |
| 18 | CEO | Spec review 2: `.proscenium/packages/` fully owned; only `install` deletes orphans | Mechanical | P5 | Prevents deleting user dirs and a stale lock after `sync` | Ownership markers |
| 19 | CEO | Spec review 2: receipt-dependent rules conditional; source identity from Gemfile.lock if dropped | Mechanical | P5 | Receipt is optional | Make receipt mandatory |
| 20 | CEO | Spec review 3: participation manifest-driven with `gemOverrides.<gem>.participate: false` opt-out | Mechanical | P1 | Dev-tooling package.json must not break upgrades | Every manifest participates |
| 21 | CEO | Spec review 3: engine reads only committed files + Bundler; local state is CLI-only (journal-in-progress check kept) | Mechanical | P5 | Removes the map.json/state conflict | Engine reads map.json |
| 22 | CEO | Spec review 3: narrow C45; excluded groups never orphan; error-not-warn rationale recorded | Mechanical | P5 | Engine cannot see projection drift | Engine projection check |
| 23 | CEO | Spec review 3: split C09/C45/C46 across Stage A/B/C gates; add cited C rows; codaset Bun >= 1.4.0 | Mechanical | P1 | Stage A could not return a clean GO otherwise | Leave gates |
| 24 | CEO | Spec review 3: matrix size and `lock`/`clean` trims | User Challenge pool (pending voices) | — | Scope cuts against the user's plan | Auto-cut |
| 25 | CEO | 0H spec review loop ended at 3 launches (scores 6, 6, 6); metrics saved | Mechanical | — | Loop cap | Fourth launch |
| 26 | CEO | 0H document approval: A) approve summary + working plan | Mechanical | P6 | Both reflect every decision above; challenges stay pending for the gate | Revise / pause |
| 27 | CEO | Both voices: re-scope v1 to a time-boxed pnpm+Bun pilot | User Challenge, accepted by user (D2) | — | Claude C1/C2 and Codex 1/3 agree; changes user's v1 (npm, all lines, all hosts) | Auto-decide |
| 28 | CEO | Both voices: narrow v1 command surface | User Challenge, accepted by user (D3) | — | Claude H1/M4/M5 and Codex 2 agree | Auto-decide |
| 29 | CEO | Both voices: split manager-independent URL scheme out of v1 | User Challenge, accepted by user (D4) | — | Claude H2 and Codex 4 agree | Auto-decide |
| 30 | CEO | Go vs Ruby CLI: keep Go | Taste | P6 | Claude H1 says Ruby; Codex keeps Go; user called Go settled | Ruby CLI |
| 31 | CEO | Engine staleness: build error in every environment | Taste | P1 | Claude M1 prefers a development warning; error prevents silent wrong graph | Dev warning |
| 32 | CEO | Participation: keep manifest-driven with opt-out | Taste | P6 | Codex 5 prefers an author opt-in signal; plan's maintainer requirement says manifest participates | Author opt-in |
| 33 | CEO | Per-gem contexts kept over one flattened `@rubygems/_gems` | Taste | P1 | Claude H4; hue's React and version-conflict evidence favour isolation | Flatten |
| 34 | CEO | Production omission of excluded-group contexts (Codex 7) | Taste (to Eng) | P3 | Install-graph design question | Decide in CEO |
| 35 | CEO | Record source manifest hash in each context; engine detects manifest drift | Mechanical | P1 | Closes silent stale-context gap (Codex 6) at a few file hashes per boot; plan line 272 already anticipates it | Structural-only |
| 36 | CEO | Accept: frozen check in deploy contract, supply-chain statement, why-not-npm rationale, helper version exit 3, context debug logging, offline fixtures, uppercase gem name case, fold addendum | Mechanical | P1/P5 | Small, in blast radius | Leave |
| 37 | DX | Product type CLI tool + library; persona Rails app developer adding a JS-carrying gem | Mechanical | P6 | Inferred from plan users and README | Gem author primary |
| 38 | DX | TTHW target Competitive (2-5 min) | Mechanical | P5 | Native installs bound the floor | Champion |
| 39 | DX | Magical moment via install success summary | Mechanical | P5 | Existing capability | Bundler-hook regeneration (deferred row 7) |
| 40 | DX | DX rows 1-5 (README section, success summary + entry-point note, consumer escape in author errors, problem/cause/fix format, projection-bump message) | Mechanical | P1/P5 | In-scope polish of the plan's own touchpoints | Leave |
| 41 | DX | Accept adoption marker; staleness error only after adoption | Mechanical | P1 | Fixes F1: literal CEO rule broke un-adopted and Yarn apps | Hard error everywhere |
| 42 | DX | Accept C48, recovery commands, error catalog, output rule, flag table, consumer escapes, docs at Stage A, tooling check, init diff, do-not-edit marker, drop warnings, URL invalidation (conditional) | Mechanical | P1/P5 | Both voices agree on dimensions 1-5; all within the plan's own touchpoints | Leave |
| 43 | DX | Keep `.proscenium/packages` (no rename to `.proscenium/gems`) | Taste | P3 | All probes measured on the current path | Rename |
| 44 | DX | Withdraw `sync --check`; CI check is `install --frozen` | Mechanical | P5 | Flag never existed in the command table | Add sync --check |
| 45 | Eng | One Bundler reader in bundled_gems.rb; orphan test via Bundler.locked_gems | Mechanical | P4 | Probe: load.specs omits BUNDLE_WITHOUT gems (94 vs 110) | Two readers |
| 46 | Eng | Peer realpath check after every install; C12/C13 bump step | Mechanical | P1 | Claude probe: pnpm splits peer silently | Check only at first install |
| 47 | Eng | Frozen production skips projection for uninstalled gems; CI frozen is authoritative | Mechanical | P3 | Docker deploys lack excluded-group sources | Require network |
| 48 | Eng | One issuer-aware lookup across five resolve paths; misses never become externals | Mechanical | P1 | Codex 1 verified at bundless.go:345, :46, mixins.go:60 | Two chains only |
| 49 | Eng | Identity = EvalSymlinks of the resolution result (settles taste row 13: real path) | Mechanical | P5 | Both voices; existing real-path pattern | Canonical manager-aware identity |
| 50 | Eng | Serve npm nested copies under .proscenium/packages/*/node_modules | Mechanical | P1 | Codex 3 verified ALLOWED_DIRECTORIES | Leave 404 |
| 51 | Eng | Canonical projected-field hash parsed in Ruby (supersedes raw bytes); shared fixture | Mechanical | P1 | Claude F5: false positives, CRLF; ~31 ms measured | Raw bytes |
| 52 | Eng | OS advisory file lock; drop --reclaim-lock; keep journal resume and --restore | Taste | P5/P1 | Claude F6 would also cut the journal; DX accepted --restore | Cut journal entirely |
| 53 | Eng | Keep Go CLI (Claude F3 again prefers Ruby) | Taste | P6 | User called Go settled; same as row 30 | Ruby CLI |
| 54 | Eng | Dev mtime refresh of the map; Go-side config-key test | Mechanical | P1 | Codex 4 / Claude F9 | Restart-only |
| 55 | Eng | Adoption = committed workspace registration (supersedes directory marker) | Mechanical | P1 | Codex 7: Git drops empty dirs | Directory existence |
| 56 | Eng | Spec allow-list, @rubygems/* lock scan exit 5, logging registry fixtures, codaset one-step migration | Mechanical | P1 | Claude F7 | Deny-list |
| 57 | Eng | Monorepo registration relative to workspace root | Mechanical | P1 | Claude F10 | Root-only |
| 58 | Eng | --offline defined as no dependency fetching | Mechanical | P5 | Codex 6 | Absolute guarantee |
| 59 | Eng | Stage A semantic regressions per dropped field | Mechanical | P1 | Codex 8 | Graph comparison only |
| 60 | Eng | Pinned CI versions, nightly canary, tiered matrix, re-estimate gate | Mechanical | P3 | Claude F8 | Newest patch in PR CI |
| 61 | Eng | Production omission of excluded-group contexts: Stage A probe, default installs all (settles row 34) | Mechanical | P3 | Codex CEO 7 | Decide now without evidence |
| 62 | Gate | UC1 pnpm+Bun pilot | User Challenge, accepted by user (D2) | — | Both voices, CEO/DX/Eng | Keep three managers |
| 63 | Gate | UC2 narrow command surface | User Challenge, accepted by user (D3) | — | Both voices | Keep all commands |
| 64 | Gate | UC3 split URL scheme | User Challenge, accepted by user (D4) | — | Both voices, three phases | Keep scheme in v1 |
| 65 | Eng re-run | Allow-list adds github:, git+https/ssh with refs; summary lists URL deps | Mechanical | P1 | Both voices: pilot gems use github: | HTTPS Git only |
| 66 | Eng re-run | Peer check only where the app declares the package; non-latest pin probe; engine re-check; no dedupe remedy | Mechanical | P1 | Both voices | Blanket equality |
| 67 | Eng re-run | .proscenium/installing marker; bundle prerequisite; stop on Proscenium version change | Mechanical | P1 | Codex 1, 3 | Lock only |
| 68 | Eng re-run | Staleness hash in Ruby only, fixed-field encoding, golden vectors | Mechanical | P5 | Claude 3 | Two implementations |
| 69 | Eng re-run | EvalSymlinks only under node_modules/ or .proscenium/packages/; link:/file: regression first | Mechanical | P1 | Claude 5 | Blanket realpath |
| 70 | Eng re-run | Undeclared-import report in inspect/install | Mechanical | P1 | Claude 7 | Request-time failure |
| 71 | Eng re-run | Hermetic fixtures, textual manifest splice, bun.lockb rejected, CI bot recipe, dotfile-deny note, locked_gems nil | Mechanical | P1/P5 | Claude 8-13 | Leave |
| 72 | Eng re-run | Reject nested-in-workspace apps in the pilot (supersedes monorepo registration) | Mechanical | P3 | Codex 5-6 | Design workspace-store mapping now |
| 73 | Eng re-run | Generation triggers add registration, linker config, Bun daemon cache key | Mechanical | P1 | Codex 7 | Leave |
| 74 | Eng re-run | Pilot GO subset; fold is a hard entry gate owned by the maintainer; Bun trusted-deps case; Puma refresh test | Mechanical | P1 | Claude 14 + security | Leave |
| 75 | Eng re-run | UC4: participation opt-in (supersedes taste row 32) | User Challenge, accepted by user (D5) | — | Codex CEO 5 + Claude Eng re-run 1; actiontext verified | Auto-decide |
| 76 | Eng re-run | Go CLI kept (Claude again suggests Ruby, Stage A in Ruby) | Taste | P6 | Same as rows 30/53 | Ruby CLI |
| 77 | Gate | UC4 participation opt-in | User Challenge, accepted by user (D5) | — | Both models across phases; actiontext verified | Manifest-driven |
| 78 | Eng pass 3 | Bun linker refusal without explicit setting; JS-only install; Ruby-owned projection + kill switch; eligibility-set cross-gem rules; opted-in missing manifest errors; alias normalization; marker on every request; explicit trustedDependencies; drop undeclared-import scan; refresh/variant/transition tests; positive controls; real-config probes; Heroku order; Git lifecycle case; mechanical fold gate | Mechanical | P1/P5 | Both voices pass 3 | Leave |
| 79 | Eng pass 3 | Keep Go CLI (Claude again: Ruby removes binaries, helper protocol, two-language projection) | Taste | P6 | User called Go settled | Ruby CLI |
| 80 | Eng pass 3 | Keep cross-gem references, C33 and conditional receipt in v1 | Taste | P6 | D1 cross-gem rule is a settled user decision | Cut until a real gem needs them |
| 81 | Gate | CLI language: Ruby, not Go (overrides taste rows 30/53/76/79) | User override (D7) | — | CLI computes nothing after UC2 + pass 3; second Ruby boot measured ~0.3 s | Go CLI |
| 82 | Eng pass 4 | Drop `--project` (Bundler.root); lock fd held by manager child; Windows shim/console qualification; unbundled child env; replace "any locked spec missing"; installed-CLI clean-process gate; `gem check` without a bundle | Mechanical | P1/P5 | Codex pass 4, each cited line verified | Leave |
| 83 | Eng pass 4 | Cut `gemOverrides.<gem>.name` from v1 instead of extending cross-gem validation to overridden names | Taste | P5 | No known gem needs it; removes the bypass instead of guarding it | Keep `name`, validate the full name map |
| 84 | Post-gate | Stage A has no time box; it ends on evidence (reverses the time box in UC1) | User decision | — | Maintainer's call after approval; the kill criterion and NO-GO rules stand | One-to-two-week time box recorded on #154 |
| 85 | Stage B | Drop pnpm 10; support pnpm 11 and 12 | User decision | — | pnpm 10 alone splits shared peers after an app upgrade (Stage A peer probe); london and platform migrate to 11 in Stage E | Keep pnpm 10 with `pnpm dedupe` on a split, or with the exit-5 error |

#### CEO 0I Temporal interrogation

- Hour 1 (foundations): the implementer must know the two existing gem bare-import chains (`bundler.go:311-337`, `bundless.go:384-417`), the two config sites that carry `RubyGems` (`builder.rb`, `runtime/server.rb:235`), and that today's unbundled dependency URLs are real paths with `.pnpm` segments.
- Hour 2-3 (core logic): ambiguities are the projection's cross-gem rewrite (needs gemspec runtime deps from the Ruby helper), whether contexts need an app edge (Stage A decides), and real-path versus canonical identity (Eng decides).
- Hour 4-5 (integration): surprises are npm hoisting making undeclared imports work, pnpm `auto-install-peers` giving an unreferenced context its own React, Bun 1.3 dot-directory discovery, and the Puma fork hazard if anything calls Go at boot.
- Hour 6+ (tests): the wish list is a fixture per real consumer shape (hue, proscenium-ui), excluded-group contexts, an in-tree path gem with a conflicting pin, and the orphan case.
- Effort: Stage A human 1-2 weeks / CC ~2-3 days; full plan human 9-15 weeks / CC ~2-3 weeks (architecture/research-heavy ratios ~3-5x). Feasibility blockers: none beyond Stage A's stated gates.

#### CEO dual voices

Native (Claude subagent, in-host, INPUT hash `c5b445de...` matched): Critical C1 over-built for three consumers and npm kept despite no consumer; C2 core premise unproven while five stages are specified, recommends a hand-written context spike in london first with a kill criterion. High H1 Go CLI unmeasured cost, recommends Ruby; H2 URL scheme is a breaking change hidden in Stage C; H3 permanent matrix for a solo maintainer; H4 per-gem contexts uncosted versus one flattened package. Medium M1 hard error is a dev cliff; M2 real gems need author edits; M3 supply-chain widening unstated; M4 perf targets theater; M5 launcher surface; M6 no why-not-npm analysis.

Outside (Codex gpt-6.1-sol, completed): P1 feasibility used as the investment gate, needs a demand gate; P1 command surface beyond the problem (keep Go, narrow to install/frozen/inspect/gem check); P1 support policy is an unbudgeted treadmill, npm has no consumer; P1 URL invariance is an asset-engine redesign; P1 automatic participation widens blast radius, wants an author signal; P1 one-pin still needs synchronization, structural staleness misses dependency changes; P2 all-group universe installs dev-gem JS in production; P2 no evidence outside authors accept the distribution tradeoff. Recommendation: re-scope to a time-boxed pnpm/Bun pilot.

```
CEO DUAL VOICES — CONSENSUS TABLE:
  Dimension                            Claude   Codex   Consensus
  1. Premises valid?                   partly   partly  CONFIRMED (core yes; Go/URL/npm premises no)
  2. Right problem to solve?           yes*     yes*    CONFIRMED (*internal problem, not yet a product)
  3. Scope calibration correct?        no       no      CONFIRMED (over-scoped)
  4. Alternatives sufficiently explored? no     no      CONFIRMED
  5. Competitive/market risks covered? no       no      CONFIRMED
  6. 6-month trajectory sound?         no       no      CONFIRMED (maintenance treadmill)
```
Disagreements (taste): CLI language (Claude Ruby, Codex Go), participation signal (Codex only), flattening (Claude only), dev-mode staleness (Claude only), production group omission (Codex only).

User Challenges queued for the final gate (both voices agree; the user's direction stands unless changed):
- UC1: v1 becomes a time-boxed pnpm + Bun pilot on london/platform/codaset, starting with hand-written contexts and a kill criterion; npm joins Yarn as "when a user appears"; support promise narrows to the apps' manager lines and hosts; a demand gate precedes the general outside-author product.
- UC2: v1 command surface narrows to `install`, `install --frozen`, `inspect`, `gem check` (plus `doctor` checks inside them); `update`/`add`/`remove`/`lock`/`migrate` (beyond a manual recipe), version handoff, the project launcher, transactional journals and the 100-gem perf gates are deferred.
- UC3: the manager-independent dependency URL scheme with peer digests leaves v1 for its own issue; v1 keeps today's real-path URLs and adds only the resolver corrections needed for context lookup and React identity.

#### CEO review sections

Current scope: SELECTIVE EXPANSION (autoplan override). Accepted: rows 3-6, 10-12, 14-23, 25-26, 35-36. Deferred: rows 7-8 (TODOS.md). Taste, provisional: 13, 30-34. Pending for the gate: UC1-UC3 (rows 9, 24, 27-29).

**Section 1: Architecture.** Examined the pipeline (Bundler, helper, generator, native manager, engine boot map, resolver) and the coupling it adds.
```
 Gemfile.lock --bundle install--> installed gem roots ----------------------------+
      |                                  |                                         |
      |                      Ruby helper (schema JSON)                     Rails boot (Ruby)
      |                                  |                              Bundler.load.specs
      v                                  v                              + ls .proscenium/packages
 proscenium CLI ---- projection ---> .proscenium/packages/<gem>/package.json      + sha of gem package.json
      |              (Go)               (committed, byte-stable, sourceManifestSha256)  |
      |                                  |                                         v
      +--> native npm/pnpm/Bun install --+--> node_modules + .proscenium/packages/*/node_modules
                                                                                   |
                       FFI config (builder.rb) + Bun daemon config (runtime/server.rb:235)
                                                                                   v
                         Go engine: participating gem bare import -> resolve from context dir only
                                     other gems -> existing bundler.go/bundless.go chains
```
Context lifecycle state machine:
```
 [absent] --gem gains manifest + install--> [committed] --manifest bytes change--> [stale: engine error]
     ^                                          |   ^                                    |
     |                                          |   +-------- install regenerates -------+
     |                              gem leaves bundle / drops manifest
     |                                          v
     +------------- install deletes -------- [orphan: engine error; sync and --frozen fail]
 invalid: frozen mode never writes; sync never deletes; user packages in .proscenium/packages are a participation error
```
Data flow (generator): happy path, manifest parsed and projected; nil path, no package.json means no context (non-participating); empty path, `{}` manifest produces a context with only name, private and the hash, which is harmless and keeps participation explicit; error path, invalid JSON or prohibited fields fail with a participation error naming the gem before any write. New coupling: the engine now reads committed files at boot (justified: it removes machine-local state from the request path). Single points of failure: the Ruby helper protocol (now versioned with exit 3) and the native manager (exit 6, native status preserved). Scaling: the boot map hashes one file per participating gem; 10x or 100x gems is still milliseconds. Rollback: delete `.proscenium/packages`, workspace registration and ignore lines, restore the previous pins; a Proscenium downgrade that predates contexts would ignore them and fall back to app-root lookup, which works under npm hoisting and breaks under pnpm/Bun, so rollback must restore the app's own pins before downgrading. Findings: the staleness gap (row 35) and the two config sites (row 21) were the architecture findings; both accepted.

**Section 2: Error and rescue map** (capability level; the CLI does not exist yet, so codepaths are the plan's algorithm steps and exit codes).
```
 CAPABILITY / STEP                 | WHAT CAN GO WRONG                          | CLASS (exit)
 ----------------------------------|--------------------------------------------|-------------
 manager selection (step 1)        | yarn signal / conflicting locks / none     | unsupported 3 / invalid 2
 Ruby phase (step 2)               | bundle install fails / frozen drift        | native 6 / drift 4
 helper query (step 3)             | schema version mismatch                    | unsupported 3 (row 36)
 manifest validation (step 5)      | bad JSON, nested workspace, file:/link:,   | invalid 2 (participation error)
                                   | hooks, bad name, unbacked @rubygems ref     |
 context write (step 6)            | frozen differs / user dir in packages      | drift 4 / invalid 2
 native JS install (step 7)        | network, auth, peer conflict, script fail  | native 6
 project lock (step 1)             | concurrent install                         | busy 7
 interruption                      | Ctrl-C mid-phase                           | interrupted 8
 engine boot map                   | missing / orphan / hash-stale context      | build error naming gem
 engine resolve                    | dependency missing from context            | actionable resolve error
 ----------------------------------|--------------------------------------------|-------------
 CLASS              | RESCUED? | ACTION                                  | USER SEES
 unsupported 3      | N (stop) | none                                    | manager/version + fix
 invalid 2          | N (stop) | none, before writes                      | gem, field, fix
 drift 4            | N (stop) | none, no lock repair                     | which input drifted
 native 6           | N (stop) | Ruby phase kept, retry resumes           | native output + status
 busy 7             | N (stop) | none                                    | holder PID, how to reclaim
 interrupted 8      | Y        | journal marks invalid, resume/restore    | recovery command
 engine stale       | N (stop) | build refused                            | gem + bin/proscenium install
```
No catch-all rescue is planned. Gap found and closed: a stale context after a gem upgrade was silent in production when nobody ran the frozen check (row 35, plus the deploy contract in row 36).

**Section 3: Security and threat model.** New attack surface: a gem's manifest now feeds the app's JS install graph (threat: malicious or compromised gem release adds a dependency with an install script; likelihood Med, impact High; mitigated by native script policy, committed context diff review, and `--frozen` drift detection; the plan now says so, row 36). Path handling: gem names come from Bundler, contexts live only under the owned directory, case collisions and traversal are C27/C29 (likelihood Low, impact Med, mitigated). Credentials: no new secrets; tokenized Git URLs redacted (mitigated). Removing the registry controller removes an HTTP surface (net reduction). No new endpoints, no PII.

**Section 4: Data flow and edge cases.**
```
 package.json -> PARSE -> VALIDATE -> PROJECT -> WRITE (staged, atomic) -> native install
   nil: no context    invalid: error 2   cross-gem ref w/o gemspec dep: error 2   frozen: compare only
   oversized/special file: error (C29)   encoding: UTF-8 only   duplicate name: collision error (C05)
```
Async ordering: invariant "a build never consumes a half-written bridge". A native command run directly takes no Proscenium lock, so `pnpm install` can overlap `bin/proscenium install`. Order A: CLI writes contexts, then pnpm reads them: consistent. Order B: pnpm reads old contexts, CLI writes new ones, CLI's own install then reconciles: consistent after the CLI's install, and the engine's hash check catches any build in between. The mechanism is atomic per-file writes plus the engine's per-build hash check; C35 covers it with controlled pause points. Edge cases mapped: 9, unhandled: 0 after rows 21, 35, 36 (uppercase gem names, excluded groups, in-tree path gems, orphans, user dirs, empty manifest, BUNDLE_WITHOUT, fresh checkout without CLI, concurrent native command).

**Section 5: Code quality.** The plan reuses the existing chains rather than adding parallel lookup (row 5, 17), keeps projection logic in one place (the CLI), and ports registry validation instead of duplicating it. Over-engineering is the dominant quality risk and is carried by UC2 and UC3 rather than re-litigated here. No other issues.

**Section 6: Tests.**
```
 NEW THING                         | TYPE        | HAPPY                 | FAILURE                    | EDGE
 projection/validation             | Go unit     | hue-shape manifest    | nested workspace error     | empty {}, uppercase name
 helper protocol                   | Ruby+Go     | batched query         | schema mismatch exit 3     | excluded groups
 native install per manager        | integration | C02, C42              | C14 optional fail          | C45 fresh checkout
 engine boot map + staleness       | Ruby/Go     | committed contexts    | orphan/hash-stale error    | BUNDLE_WITHOUT context
 context-only resolve              | Go          | C04, C46              | missing dep diagnostic     | in-tree path gem conflict
 Bun daemon config site            | JS (bun)    | gem import in bun test| stale context error        | none
 frozen drift                      | E2E         | C08 repeat            | C09 changed manifest       | orphan exit 4
 concurrency/interruption          | E2E         | C35                   | C34 each phase             | native cmd overlap
```
2am-Friday test: london fresh checkout, plain `pnpm install`, `bin/rails assets:precompile`, then a page that imports hue's React component renders with one React. Hostile QA test: bump hue in Gemfile.lock without running install and deploy. Chaos test: kill the CLI between context write and native install, then build. Flakiness risk: real registries in CI; fixtures use local tarballs (row 36). Gaps found: the Bun daemon config site and boot-map tests were missing; added via rows 21 and 36.

**Section 7: Performance.** No database. Boot cost is a directory listing plus one SHA-256 per participating gem (single-digit files for known apps). The CLI's p95 target for 100 gems is out of proportion to known usage (UC2). No other issues.

**Section 8: Observability.** CLI JSON events and exit codes are well specified. The engine side lacked a trace of which imports were routed to a context; added (row 36). A bug reported three weeks later is reconstructable from the committed context diff, Gemfile.lock and the engine's named error. No dashboards apply to a local developer tool.

**Section 9: Deployment and rollout.** Rollout is per-app adoption behind an experimental label, which acts as the feature flag. Mixed-version risk: an older Proscenium ignores contexts (see Section 1 rollback). Post-deploy check: the deployment sequence's asset smoke check plus `install --frozen` in CI (row 36). No other issues.

**Section 10: Long-term trajectory.** Reversibility 3/5 overall (contexts and registration are owned and removable); the URL scheme change is 2/5 because it changes public asset URLs and manifest keys, which is part of why UC3 exists. Debt items: 3 (permanent manager-line matrix, two engine config sites to keep in step, the addendum-versus-body drift until it is folded). Path dependency: committing to `.proscenium/packages` and `@rubygems/<gem>` names is cheap to keep and matches existing URLs. Platform potential: the context map is the hook later tools (Node/Vitest adapters in TODOS.md) would need.

**Section 11: Design.** SKIPPED (no UI scope).

#### CEO required outputs

NOT in scope:
- Deferred: Bundler `after-install-all` regeneration (row 7, TODOS P3); `inspect --why` (row 8, TODOS P4).
- Rejected: none in this phase. UC1-UC3 are pending at the gate, not rejected or accepted.

What already exists: `bundled_gems.rb` (Bundler authority, reused for the boot map); `bundler.go:311-337` and `bundless.go:384-417` (gem bare-import chains, retargeted); `bundless.go:80` real-path gate (extended); `utils.UrlPathFromFsPath` (single URL rule, unchanged in v1 if UC3 is taken); registry controller validation (ported to manifest validation, then removed); `runtime/server.rb` Bun daemon config (second config site); Rakefile `PLATFORMS` and `bin/verify-installed-gem` (extended for the CLI binary).

Dream state delta: this plan reaches the 12-month ideal's mechanics (gem package.json drives native installs, one pin) for three internal apps; it does not yet show outside authors adopt it, which UC1's demand gate would measure.

Failure modes registry:
```
 CODEPATH                 | FAILURE MODE                    | RESCUED? | TEST?      | USER SEES?            | LOGGED?
 -------------------------|---------------------------------|----------|------------|-----------------------|--------
 context generation       | invalid manifest                | stop     | Go unit    | gem + field + fix     | JSON event
 context generation       | uppercase gem name              | stop     | C27        | override hint         | JSON event
 frozen install           | context drift                   | stop     | C09        | exit 4 + input        | JSON event
 native install           | network/auth/peer failure       | stop     | C14/C31    | native output         | native
 engine boot              | missing/orphan/hash-stale       | stop     | C45/C36    | build error + gem     | Rails log
 engine resolve           | dep missing from context        | stop     | C04        | actionable diagnostic | debug
 production deploy        | gemspec-dep change, no --frozen | N        | C45 (CLI)  | silent wrong graph    | no
 interruption             | Ctrl-C mid-phase                | resume   | C34        | recovery command      | journal
 concurrent native cmd    | overlap with CLI writes         | Y        | C35        | consistent after run  | no
```
One residual row: a gemspec runtime-dependency change (not a manifest change) deployed without `--frozen` is silent. It is not a CRITICAL GAP by the registry rule because it is tested (C45 through the CLI) and the deploy contract requires `--frozen`; it is listed as a known limit.

Stale diagram audit: the plan's own pipeline diagram ("Architecture and persistent artifacts") omits the engine's boot map and the Bun daemon config site; folding the addendum (row 36) updates it. No other ASCII diagrams in touched files.

Implementation Tasks (CEO):
- [ ] **T1 (P1, human: ~3d / CC: ~4h)** — pilot — Hand-write `.proscenium/packages/hue/package.json` in london, register it, run pnpm, and route hue's bare imports through the context with a test-only seam; record the verdict.
  - Surfaced by: Dual voices, Claude C2 / Codex recommendation
  - Files: to be determined (london app, `internal/plugin/bundler.go`, `internal/plugin/bundless.go`)
  - Verify: hue page renders with one React instance (`===` check) in bundled and unbundled mode
- [ ] **T2 (P1, human: ~2h / CC: ~15min)** — plan — Fold the accepted requirements into their sections and delete superseded `map.json`/step 8-9 text.
  - Surfaced by: Row 36, Claude C2
  - Files: docs/plans/154-package-manager.md
  - Verify: no requirement appears only in the trailing list; `grep map.json` shows CLI-only usage
- [ ] **T3 (P2, human: ~1h / CC: ~10min)** — plan — Add the "Why not publish to npm" rationale and the supply-chain statement.
  - Surfaced by: Claude M3/M6
  - Files: docs/plans/154-package-manager.md
  - Verify: sections present and cited from Security and Decision
- [ ] **T4 (P2, human: ~2h / CC: ~20min)** — plan — Add the new conformance cases (C36 orphan, in-tree path gem conflict, C32 excluded-group context, C27 uppercase name) and the Stage A/B/C gate split.
  - Surfaced by: Spec review 3
  - Files: docs/plans/154-package-manager.md
  - Verify: each accepted requirement cites a matrix row that a stage gates

CEO completion summary:
```
  +====================================================================+
  |            MEGA PLAN REVIEW — COMPLETION SUMMARY                   |
  +====================================================================+
  | Mode selected        | SELECTIVE EXPANSION (autoplan override)     |
  | System Audit         | citations verified; pnpm pin stale; today's |
  |                      | unbundled URLs already carry .pnpm segments |
  | Step 0               | 4 premises (2 challenged), 5 delight items, |
  |                      | 3 spec-review launches (6/6/6)              |
  | Section 1  (Arch)    | 2 issues found (staleness, config sites)    |
  | Section 2  (Errors)  | 10 error paths mapped, 1 GAP (closed)       |
  | Section 3  (Security)| 1 issue found, 0 High unmitigated           |
  | Section 4  (Data/UX) | 9 edge cases mapped, 0 unhandled            |
  | Section 5  (Quality) | 0 new issues (over-engineering -> UC2/UC3)  |
  | Section 6  (Tests)   | Diagram produced, 2 gaps (closed)           |
  | Section 7  (Perf)    | 0 new issues (perf gates -> UC2)            |
  | Section 8  (Observ)  | 1 gap found (closed)                        |
  | Section 9  (Deploy)  | 1 risk flagged (downgrade with contexts)    |
  | Section 10 (Future)  | Reversibility: 3/5, debt items: 3           |
  | Section 11 (Design)  | SKIPPED (no UI scope)                       |
  +--------------------------------------------------------------------+
  | NOT in scope         | written (2 items)                           |
  | What already exists  | written                                     |
  | Dream state delta    | written                                     |
  | Error/rescue registry| 10 rows, 0 CRITICAL GAPS                    |
  | Failure modes        | 9 total, 0 CRITICAL GAPS                    |
  | TODOS.md updates     | 2 items proposed                            |
  | Scope proposals      | 5 proposed, 1 accepted                      |
  | CEO plan             | written (ceo-plans/2026-10-03-154-...)      |
  | Outside voice        | codex completed                             |
  | Lake Score           | N/A (no coverage-scored questions)          |
  | Diagrams produced    | 5 (architecture, lifecycle, error, data     |
  |                      | flow, tests)                                |
  | Stale diagrams found | 1                                           |
  | Unresolved decisions | 3 (UC1-UC3, final gate)                     |
  +====================================================================+
```
Approval readiness: PASS for rows 3-6, 10-12, 14-23, 25-26, 35-36 (autoplan auto-decisions under the 6 principles); taste rows 13, 30-34 provisional; UC1-UC3 unresolved by design.

#### Phase 2 (Design): SKIPPED

No UI scope detected (see run header). This is a skip, not a completed review.

#### DX Step 0 (Phase 2.5)

Product type: CLI tool (primary) plus a library integration (the asset engine's resolver). Auto-decided (P6): the plan's surface is `proscenium install`/`inspect`/`gem check` plus gem-author metadata. Mode: DX POLISH (autoplan override). Prior DX reviews: none. Existing developer docs: README "Installation" (`gem 'proscenium'`), "Import from NPM", the `@rubygems/` path note at README:547, and two guides (`docs/guides/new_rails_app.md`, `migrate_from_sprockets.md`). Nothing documents how a gem's own JS dependencies get installed today; the registry route was never in the README.

```
TARGET DEVELOPER PERSONA
========================
Who:       Rails developer on a small product team (london/platform shape) adding a gem that ships
           frontend components with their own JS dependencies (hue shape)
Context:   Gemfile change in a feature branch; the app already uses Proscenium with pnpm or Bun
Tolerance: ~10 minutes and one unfamiliar command before reverting to a github: pin
Expects:   `bundle install` plus their own package manager; errors that say which gem and what to run
```
Secondary persona: the gem author (hue's maintainer) shipping components; they need `gem check` and the guide.

Developer perspective (empathy narrative, predicted, not observed): "I added `gem 'hue'` and ran `bundle install`. The README tells me how to import from npm, and that files in gems are `@rubygems/hue/...`, but not how hue's React and sourdough-toast get installed. I import hue's component and the build says it cannot resolve `sourdough-toast` from hue. Last time someone added `"@rubygems/hue": "github:harleytherapy/hue#<sha>"` to package.json, so I copy that, pick a SHA, and now I have two pins. Under the plan, I run `bundle exec proscenium install`; it tells me it registered `.proscenium/packages/*` in pnpm-workspace.yaml, wrote `.proscenium/packages/hue/package.json`, added three .gitignore lines and `bin/proscenium`, and installed hue's dependencies with pnpm. I commit those files. Two weeks later a teammate bumps hue and forgets the command; their page fails to build with an error naming hue and `bin/proscenium install`. That is fine. What would lose me: an author-contract error about hue's React that I, the consumer, cannot fix."

Competitive benchmark (clock: app already on Proscenium; start = add the gem to Gemfile; useful result = a page renders the gem's component with its JS dependencies resolved):

| Tool | Start → result | Time + evidence type | DX choice | Source |
|------|----------------|----------------------|-----------|--------|
| npm-published gem JS (turbo-rails / stimulus-rails) | Gemfile + `npm i @hotwired/turbo-rails` or an install generator | ~2-3 min, estimated | Two pins (gem + npm) kept in sync by the author's release | discuss.rubyonrails.org thread above |
| importmap-rails `bin/importmap pin` | pin from CDN, no node_modules | ~1-2 min, estimated | No install step; CDN or vendored files | importmap-rails README (in-distribution) |
| Today in london/platform | Gemfile + hand-written `github:` pin + pnpm install | 5-10 min, estimated (SHA lookup, undocumented) | Second pin that drifts | plan "Known consumers" |
| Today in codaset | Gemfile + scoped registry in .npmrc + `bun add` | 5+ min first time, estimated; needs a hosted service | Registry dependency | plan "Known consumers" |
| This plan | Gemfile + `bundle install` + `bundle exec proscenium install` | ~2-4 min, estimated; dominated by the two installs | One pin; committed contexts | this plan |

TTHW target: Competitive (2-5 min). Auto-decided (P5): Champion (<2 min) is bounded below by `bundle install` plus a pnpm/Bun install, which Proscenium does not control.

Magical moment: the developer runs one command after `bundle install` and the gem's component renders, with no package.json edit for the gem. Vehicle chosen (P5, lowest effort within existing capability): the `install` success summary names each participating gem, the package manager used and the dependency count ("hue: 3 dependencies via pnpm 12.8.1; proscenium-ui: 1 via pnpm"), followed by the exact files to commit. Alternative not chosen: regeneration from `bundle install` alone via the Bundler hook (deferred TODO, row 7).

Developer journey (traced against the plan; friction resolutions are auto-decisions logged below):
```
STAGE           | DEVELOPER DOES                                 | FRICTION POINTS                                  | STATUS
----------------|------------------------------------------------|--------------------------------------------------|--------
1. Discover     | reads README for gem JS dependencies           | no section exists; registry notes to be removed  | fixed (DX row 1)
2. Install      | bundle install; bundle exec proscenium install | two entry points (bundle exec vs bin/proscenium) | fixed (DX row 2)
3. Hello World  | imports the gem component, renders the page    | gem-author error the consumer cannot fix         | fixed (DX row 3)
4. Real Usage   | teammate bumps gem, pnpm add, deploy           | forgot install -> named build error (designed)   | ok
5. Debug        | reads an error, runs inspect/doctor            | error format not pinned to problem+cause+fix     | fixed (DX row 4)
6. Upgrade      | upgrades Proscenium itself                     | projection version bump churns contexts, CI fails| fixed (DX row 5)
```

First-time developer report (persona above, predicted from the plan):
```
T+0:00  Adds gem 'hue', runs bundle install. Fine.
T+0:40  Imports hue's component; build fails resolving sourdough-toast from hue. Needs to know the next command.
T+1:00  README has no answer today -> DX row 1 adds "JavaScript dependencies from gems" with the one command.
T+1:30  Runs bundle exec proscenium install; sees registration edits, bin/proscenium, contexts, pnpm output.
T+2:30  Page renders. Unsure whether to commit .proscenium/packages -> the success summary lists files to commit.
T+3:00  Later uses bin/proscenium install; wonders why two spellings -> DX row 2 states the rule in the output.
```

<!-- autoplan-accepted:dx -->
- The README gains a "JavaScript dependencies from gems" section placed after "Import from NPM": the one-command flow (`bundle install`, then `bundle exec proscenium install`), what gets committed, the frozen CI step, and a link to the gem author guide; it replaces any registry setup text.
- `proscenium install` success output names each participating gem with its package manager and dependency count, then lists the exact files to commit (contexts, workspace registration, `.gitignore`, `bin/proscenium`), and on first run states that later runs can use `bin/proscenium install` and that `bundle exec proscenium install` keeps working.
- When a participation error comes from a gem's own manifest (a gem-author problem such as a nested workspace, an install hook or an unbacked `@rubygems/*` reference), the consumer-facing message names the gem, the cause, the fix for the gem author, and the consumer escape: `gemOverrides.<gem>.participate: false` in proscenium.json, which restores today's app-context behaviour for that gem. Verified by C18 and C26 asserting the escape is printed.
- Every CLI and engine error the plan defines states problem, cause and fix (a command or file edit) and, where a guide section exists, its anchor; the JSON event carries the same `code` plus a `fix` field. Verified by a test per exit code.
- A projection version change between Proscenium releases is named in the CHANGELOG, and `install --frozen` reports it as "context projection changed from <old> to <new>; run bin/proscenium install and commit .proscenium/packages" rather than a generic drift error. Verified by a frozen-run test across a projection version bump.
- Adoption is explicit: an app has adopted the bridge once `.proscenium/packages/` exists (first `install` creates it). Before adoption, and in any Yarn project, the engine keeps today's behaviour for every gem and logs one boot-time notice per process naming the gems with a package.json and `bundle exec proscenium install` (for Yarn: that Yarn is unsupported and gem dependencies stay app-managed). The CEO engine-staleness build error applies only after adoption. Verified by a new row: upgrade Proscenium on an un-adopted pnpm app with a manifest gem and on a Yarn app; both still build.
- A new conformance row C48 measures first run: fresh `rails new`, add Proscenium and one manifest gem, add an import of the gem's component, run the documented commands, and the page renders. It asserts the command count (3 after `bundle add`), the success-summary text, and records wall time on warm caches against the Competitive (2-5 min) target. It includes the no-package.json/no-manager case, where `install --manager <name>` is required and the error names it. `install` accepts `--manager`; `init` stays optional.
- The CI drift check is `bin/proscenium install --frozen`. The `sync --check` alternative named in the CEO requirement is withdrawn; no such flag exists. `install` is documented as the only command a developer needs; `sync`, `lock` and `clean` are listed as advanced. `gem check` with no argument checks the gem in the current directory.
- One reference table defines every flag, environment variable and `proscenium.json` key with its exact spelling, including the manager override and the experimental-version override, and `proscenium.json` has a published schema whose `gemOverrides.<gem>` keys are `participate` (boolean) and `name` (context name override).
- Output streams: by default stdout carries the human summary and native tool logs go to stderr; `--json` switches stdout to newline-delimited schema-versioned events; `inspect --json` prints one JSON document. Exit 1 means an unexpected internal error and always prints a bug-report hint.
- Each error has a stable code (for example `PSM-E-PARTICIPATION-HOOK`) with a guide anchor, and golden-output tests pin the human text and JSON for every code and exit status.
- Recovery is named: re-running `bin/proscenium install` resumes an interrupted install from its journal; `bin/proscenium install --restore` restores the owned files to the journal's snapshot; a stale project lock is reclaimed by `install --reclaim-lock` only after the CLI confirms the recorded PID and start identity are gone. The engine's "install in progress" refusal and exit 8 both print the matching command. Verified by C34 asserting the printed command.
- Engine staleness and the pre-adoption notice are logged once at Rails boot in development and test (Ruby only, no Go call at boot), shown in the development error page body, and reported by `doctor`.
- Specific messages: frozen drift prints a unified diff of each differing context and says when a context was edited by hand; the Yarn error offers switching manager or keeping app-managed dependencies; an existing user-owned `bin/proscenium` is left alone and the output says so and how to run the packaged launcher instead.
- The consumer quickstart and the gem author guide are drafted at the end of Stage A and exercised against the Stage A fixtures; the author contract is one checklist whose executable form is `gem check`, with an example package.json (React as a peer). The guides include a first-run transcript, a sample context file, a sample PR diff, a Dockerfile layering example and a CI recipe, and the `bin/setup` line.
- Consumer escapes are complete: every participation error caused by a gem's manifest (including cross-gem references that need a gemspec line the consumer cannot add) prints the copyable `gemOverrides` snippet, states that the app must then declare that gem's JS dependencies itself, and names native overrides (pnpm `overrides`, npm `overrides`, Bun `overrides`) as the way to dedupe a gem's plain React dependency.
- Stage E checks whether london, platform and codaset rely on `node_modules/@rubygems/<gem>` for TypeScript, ESLint or test-runner resolution, and the migration guide gives the tsconfig `paths` recipe that replaces it.
- `proscenium init` prints the owned edits as a unified diff before writing, so a developer can preview first-run changes.
- Each generated context carries a static `"description": "Generated by Proscenium from the <gem> gem. Do not edit; run bin/proscenium install."` field, and the PR review guidance says contexts are generated.
- A manager or Node line that will be dropped at the next Proscenium release triggers an `install` warning naming the line and the release one release ahead, and the CHANGELOG lists it; the upgrade guide gives the tool-and-lock migration order and its rollback boundary.
- If the manager-independent URL scheme stays in v1 (UC3), Stage C specifies how precompiled manifests and cached module URLs are invalidated across the change and adds a deploy test for it.
<!-- /autoplan-accepted:dx -->


#### DX dual voices

Claude SUBAGENT (DX — independent review), in-host, INPUT hash `5f8798ec...` matched: Critical F1 engine staleness rule breaks un-adopted apps on upgrade ("adopted" undefined; Yarn apps hard-error). High F2 no first-run gate; F7 no error contract; F8 no recovery command; F11 docs scheduled last and scattered; F14 consumer cannot fix third-party gem errors; F15 native importability of `@rubygems/*` lost for TS/lint/tests. Medium F3 overlapping verbs and undefined `sync --check`; F4 no override spellings; F5 vocabulary leaks; F6 output streams ambiguous; F9 staleness only at request time; F10 messages undefined; F12 no Dockerfile example; F13 addendum fold; F16 no first-run preview; F17 no "do not edit" marker.

Codex SAYS (DX — developer experience challenge), gpt-6.1-sol, completed: P1 interrupted installs have no recovery command; P1 a Proscenium upgrade can force a tooling migration without notice; P2 hello world not specified end to end (no-manager case, `--manager` only on `init`); P2 gem-author errors lack a consumer escape; P2 automation contract ambiguous (stdout JSON, `inspect --json`, `sync --check`, argumentless `gem check`); P2 URL change has no upgrade contract. Recommendation: revise around a time-boxed pnpm+Bun pilot.

```
DX DUAL VOICES — CONSENSUS TABLE:
  Dimension                           Claude  Codex  Consensus
  1. Getting started < 5 min?          gap     gap    CONFIRMED (not specified or gated end to end)
  2. API/CLI naming guessable?         gap     gap    CONFIRMED (verbs, overrides, output contract)
  3. Error messages actionable?        gap     gap    CONFIRMED (no recovery command, no consumer escape)
  4. Docs findable & complete?         gap     gap    CONFIRMED (late, scattered, no copy-paste first run)
  5. Upgrade path safe?                gap     gap    CONFIRMED (F1 adoption; tool-line drops; URL change)
  6. Dev environment friction-free?    gap     not raised  N/A (single voice: F9, F12, F16, F17)
```
Single-voice critical flagged: F1 (Claude only). Accepted anyway: it corrects this review's own CEO requirement, whose literal reading would break platform and london on upgrade. Cross-phase theme: Codex repeats the CEO pilot recommendation (UC1).

#### DX passes

**Pass 1, Getting Started: 5/10 → 8/10.** Evidence: three actions after `bundle add` (plan "Decision and product contract"), no TTHW target, no first-run test, `--manager` only on `init`. A 10 is one documented golden path that a stranger runs in a fresh `rails new` and sees the component render in under 5 minutes, with the summary telling them what to commit. Fixed by C48, `install --manager`, the success summary (DX rows 1-2) and the quickstart drafted at Stage A. Residual: wall time is dominated by native installs; Competitive, not Champion.

**Pass 2, CLI design: 5/10 → 7/10.** Evidence: fifteen commands, overlapping `install`/`sync`/`lock`, undefined `sync --check`, override spellings missing, stdout rule ambiguous. A 10 is one daily verb with everything else discoverable and clearly advanced. Fixed by naming `install` the only daily command, the flag/env/config table, the output-stream rule and `gem check` defaulting to the current gem. Residual: command count stays until UC2 is decided at the gate. Taste row 43: keep `.proscenium/packages` rather than renaming to `.proscenium/gems` (probes, D1 evidence and the Bun floor were all measured on the current path).

**Pass 3, Errors: 4/10 → 8/10.** Traced three paths. (a) Stale context after a teammate bumps hue: today predicted "could not resolve sourdough-toast"; required "hue's JS dependencies changed (package.json hash differs from .proscenium/packages/hue). Run bin/proscenium install and commit .proscenium/packages/hue. [PSM-E-STALE-CONTEXT]". (b) hue declares an install hook: required problem (hue's package.json has a postinstall), cause (Proscenium never runs gem hooks), author fix, consumer escape snippet. (c) Ctrl-C mid-install, then a page load: required "An interrupted bin/proscenium install left .proscenium in an incomplete state. Run bin/proscenium install to resume, or bin/proscenium install --restore. [PSM-E-INTERRUPTED]". All three now have pinned codes, golden tests and named commands.

**Pass 4, Docs: 3/10 → 7/10.** Evidence: README has no gem-dependency section; guides land in Stage E; author contract spread over five sections. Fixed by the README section, Stage A drafts tested against fixtures, the one-checklist author contract, copy-paste transcript, sample context, PR diff, Dockerfile and CI recipe. Residual: docs quality is only provable once written.

**Pass 5, Upgrade: 3/10 → 7/10.** Evidence: F1 (un-adopted apps would hard-error), support-line drops with no notice, projection bumps, URL change for pnpm/Bun apps, lost `node_modules/@rubygems/*` resolution for tooling. Fixed by the adoption marker, one-release-ahead drop warnings, the projection-bump message, the URL invalidation requirement (conditional on UC3) and the Stage E tooling check. Residual: no codemod; `migrate` is the codemod and its scope is under UC2.

**Pass 6, Dev environment: 6/10 → 8/10.** Evidence: committed contexts keep `pnpm install`/`bun install` working (plan "Fresh-checkout probes"); CI and Dockerfile flow only in prose; staleness surfaced only on asset requests. Fixed by boot-time logging in development/test (Ruby only, respecting the Puma fork rule), the Dockerfile and CI recipe, `bin/setup`, the `init` diff preview and the "do not edit" marker. Residual: Windows path only qualified in Stage D.

**Pass 7, Community: 5/10 → 6/10.** Evidence: open-source repo, issue tracker in use (#154), no external consumers yet, no example gem. The gem author guide's example package.json and `stage_a_hue_shape` (public) serve as the reference gem. No new channel proposed; the CEO demand gate (UC1) is where outside-author adoption gets measured.

**Pass 8, DX measurement: 2/10 → 6/10.** Evidence: only orchestration overhead is measured. Fixed by C48's recorded wall time on the documented clock (add gem to rendered component). No telemetry or recurring audit proposed (each would be its own decision); `/devex-review` after Stage E is the boomerang check.

```
+====================================================================+
|              DX PLAN REVIEW — SCORECARD                             |
+====================================================================+
| Dimension            | Score  | Prior  | Trend  |
|----------------------|--------|--------|--------|
| Getting Started      |  8/10  |  5/10  |  +3 ↑  |
| API/CLI/SDK          |  7/10  |  5/10  |  +2 ↑  |
| Error Messages       |  8/10  |  4/10  |  +4 ↑  |
| Documentation        |  7/10  |  3/10  |  +4 ↑  |
| Upgrade Path         |  7/10  |  3/10  |  +4 ↑  |
| Dev Environment      |  8/10  |  6/10  |  +2 ↑  |
| Community            |  6/10  |  5/10  |  +1 ↑  |
| DX Measurement       |  6/10  |  2/10  |  +4 ↑  |
+--------------------------------------------------------------------+
| TTHW                 | ~2-4 min (est.) | 5-10 min today (est.) | ↓ |
| Competitive Rank     | Competitive                                  |
| Magical Moment       | designed via install success summary         |
| Product Type         | CLI tool + library integration               |
| Mode                 | POLISH                                       |
| Overall DX           |  7/10  |  4/10  |  +3 ↑  |
+====================================================================+
| DX PRINCIPLE COVERAGE                                               |
| Zero Friction      | covered (C48, one daily command)               |
| Learn by Doing     | covered (transcript, sample files)             |
| Fight Uncertainty  | covered (codes, recovery commands)             |
| Opinionated + Escape Hatches | covered (gemOverrides, native overrides) |
| Code in Context    | covered (Dockerfile, CI, PR diff)              |
| Magical Moments    | covered (success summary)                      |
+====================================================================+
```
No dimension below 6 after fixes; TTHW is under 10 minutes.

```
DX IMPLEMENTATION CHECKLIST
============================
[ ] Time to hello world < 5 min (C48, warm caches)
[ ] Installation is one command after bundle install
[ ] First run prints per-gem summary and files to commit
[ ] Magical moment delivered via install success summary
[ ] Every error: problem + cause + fix + guide anchor + stable code (golden tests)
[ ] install is the only daily command; flag/env/config table published
[ ] gemOverrides schema published; consumer escape printed in author errors
[ ] Docs have copy-paste transcript, Dockerfile, CI recipe, sample context, PR diff
[ ] Upgrade path: adoption marker, line-drop warnings, projection-bump message
[ ] Breaking URL change (if UC3 keeps it) has an invalidation procedure and deploy test
[ ] Works in CI with install --frozen; no interactive prompts
[ ] Changelog names projection and support-line changes
```

DX NOT in scope: telemetry of first-run time (would need its own decision), a hosted docs search, a community channel, renaming `.proscenium/packages` (taste row 43). DX What already exists: README "Installation" and "Import from NPM", the `@rubygems/` path note, `docs/guides/new_rails_app.md`, the plan's exit-code table and JSON events, `migrate --plan`.

DX Implementation Tasks:
- [ ] **T5 (P1, human: ~2h / CC: ~15min)** — engine — Define adoption by `.proscenium/packages/` and gate the staleness error on it.
  - Surfaced by: DX F1
  - Files: docs/plans/154-package-manager.md (then `lib/proscenium/bundled_gems.rb` at Stage C)
  - Verify: un-adopted pnpm app and Yarn app both build after upgrading Proscenium
- [ ] **T6 (P1, human: ~1d / CC: ~1h)** — tests — Add C48 first-run row with command count, summary text and timing.
  - Surfaced by: DX F2, Codex 3
  - Files: docs/plans/154-package-manager.md, test/package_manager/ (to be determined)
  - Verify: C48 passes on macOS with pnpm and Bun
- [ ] **T7 (P2, human: ~3h / CC: ~20min)** — CLI — Publish the error-code catalog, recovery commands, output-stream rule and flag/env/config table.
  - Surfaced by: DX F3, F4, F6, F7, F8, Codex 1, 5
  - Files: docs/plans/154-package-manager.md
  - Verify: every exit code and participation error has a code, fix and guide anchor
- [ ] **T8 (P2, human: ~1d / CC: ~2h)** — docs — Draft quickstart and author guide at the end of Stage A with transcript, Dockerfile, CI recipe.
  - Surfaced by: DX F11, F12
  - Files: README.md, docs/guides/ (to be determined)
  - Verify: a fresh reader follows the quickstart against the Stage A fixtures

#### Eng Step 0 (Phase 3): scope challenge

Code read for this step: `lib/proscenium/bundled_gems.rb` (whole file), `lib/proscenium/builder.rb:200-240` (FFI config hash), `internal/types/types.go` (`RubyGems map[string]string`), `internal/plugin/bundler.go:300-340`, `internal/plugin/bundless.go:60-130` and `:380-420`, `internal/utils/utils.go:375-412`, `lib/proscenium/runtime/server.rb:230-240`, `.github/workflows/main.yml:185-195`, `fixtures/dummy/package.json` and its `node_modules` links.

What already solves each sub-problem: Bundler authority and gem roots (`BundledGems.paths`, memoized per process at `bundled_gems.rb:8`); per-gem bare-import resolve dir (`bundler.go:311-337`); three-step unbundled chain (`bundless.go:384-417`); real-path normalization (`bundless.go:80-95`); single fs-to-URL rule (`UrlPathFromFsPath`, `utils.go:379`); two config sites carrying `RubyGems` (`builder.rb:218`, `runtime/server.rb:235`); registry validation to port (`registry_controller.rb`, which took six fix commits in the last month, `497ea328`..`73dc712f`, a maintenance cost the plan removes).

Retrospective: `bundled_gems.rb` and the plugins were reworked twice recently (`c9cb03c8` prefix match replacing a regex, `683dc375` innermost nested gem root). Both touch the exact gem-root mapping Stage C extends, so nested-gem and prefix cases belong in Stage C's regressions. No reverts in these paths.

Bounded probe (this repo, `BUNDLE_WITHOUT=development`): `Bundler.load.specs` returned 94 gems, `Bundler.locked_gems.specs` 110; the 16 missing are the excluded group (`appraisal`, `benchmark-ips`, ...). So the engine's boot map cannot tell an excluded-group context from an orphan using `Bundler.load.specs`; it must read `Bundler.locked_gems` for that test.

Complexity check: the plan proposes well over 8 changed files (CLI package, Ruby helper, launcher, engine config in Ruby and Go, two plugins, utils, runtime, Rakefile, gemspec, release and CI workflows, registry removal, docs) and more than 2 new services (Go CLI, Ruby Bundler helper, project launcher, journal/lock). The gate trips. Autoplan override: scope is never reduced in Eng (P2); the scope cuts are already queued as UC1-UC3 for the user. Structure: original arrangement kept, with one smaller-arrangement note: the Ruby helper and the engine's boot map both read Bundler, so they share one Ruby module (`lib/proscenium/bundled_gems.rb` grows `locked_names` and `context_map`) rather than two readers. Search check: Bundler exposes `Bundler.locked_gems` and the `after-install-all` plugin hook (Layer 1); npm/pnpm/Bun workspaces are Layer 1; the dependency-only workspace is Layer 3 and Stage A's job to prove. Distribution: the CLI binary rides the existing `PLATFORMS`/release workflow (plan "CLI contract"); no new channel. Scope Challenge result: scope accepted as-is.

<!-- autoplan-accepted:eng -->
- The engine's orphan test uses `Bundler.locked_gems` (Gemfile.lock), not `Bundler.load.specs`, which omits `BUNDLE_WITHOUT` groups (probe: 94 of 110 gems with `BUNDLE_WITHOUT=development`). Gem roots for participating gems still come from `Bundler.load.specs`. Verified by C32's excluded-group context case.
- `lib/proscenium/bundled_gems.rb` is the one Ruby reader of Bundler for both the engine boot map and the CLI's Ruby helper (adding the locked-name set and the context map beside `paths`), so the two never disagree about which gems exist.
- Stage C's regressions include the nested-gem-root and prefix-match cases fixed in `683dc375` and `c9cb03c8`, applied to context routing.
- Peer identity is checked after every install, not only "where required": for each peer a context declares, the realpath resolved from the context must equal the realpath resolved from the app root; a mismatch fails the install naming the package and the native fix (`pnpm dedupe`), and CI can run `pnpm dedupe --check`. Evidence (Eng probe, pnpm 10.34.4): after the app bumps its peer provider and re-installs, pnpm leaves the context on the old version with exit 0, with or without an app `workspace:*` edge and in a nested layout; npm and Bun kept one copy. C12 and C13 gain a "bump the app's peer provider after the first lock, then install" step on every manager line.
- `install --frozen --production` (and `--offline`) does not need sources for gems in excluded groups: for a gem whose source is not installed, it skips the projection comparison, trusts the committed context and reports each skip; the non-production CI `install --frozen` run is the authoritative drift check. C32 asserts no network access in that mode.
- One issuer-aware dependency lookup serves every path that resolves a participating gem's external import: the `bundler.go:311-337` branch, the `bundless.go:384-417` chain, the bare-with-extension shortcut at `bundless.go:345-349` (which today emits `/node_modules/<specifier>` without resolving), the CSS-module and SVG resolve at `bundless.go:46`, and CSS mixin lookup through `resolver.Resolve` (`internal/css/mixins.go:60`). For participating gems a resolution miss is a named error, never converted into a browser external. Fixtures cover each path with a version that conflicts with the app's. This supersedes the CEO requirement's "two paths" wording and subsumes the TODOS.md item "Resolve a gem's bare-with-extension imports against the gem when unbundling" for participating gems.
- Package identity is the real path of the resolution result (EvalSymlinks on the resolved file, not only on the resolve directory), applied the same way to the app's and every context's resolves in bundled, unbundled, resolve-only and Bun-harness modes. Stage A executes an unbundled identity probe (two link paths to one React load as one module in the browser), not only a bundled `===` check. This settles the real-path versus canonical-identity choice the CEO requirement left open.
- Real-path URLs for npm's nested copies under `.proscenium/packages/<gem>/node_modules/` are served: the serving allow-list (`ALLOWED_DIRECTORIES` in `lib/proscenium.rb`) and URL mapping cover that path with the same containment rules as `node_modules`, and C21/C22 assert a nested copy's font and chunk URLs load.
- If the manager-independent URL scheme stays in v1 (UC3), its identity also covers source and patch provenance (Git revision, tarball URL, applied patch) and the instance's own dependency environment, so two distinct installed copies never share a URL.
- The staleness hash covers a canonical serialization of the projected fields (parsed in Ruby; measured about 31 ms to parse 184 manifests averaging 1.2 KB), not raw manifest bytes, so edits to scripts, devDependencies or `version` and CRLF checkouts do not raise. This supersedes the CEO requirement's raw-byte hash and its "no JSON parsing at boot".
- The CLI's project lock is an OS advisory file lock (`flock`/`LockFileEx`) on `.proscenium/lock`, released when the process dies; PID/start-identity reclamation and `--reclaim-lock` are dropped (superseding that part of the DX requirement). The engine checks the lock non-blocking when it creates a mapping generation and reports "install in progress" with the command to wait for or re-run. Guarantees during a direct native command running alongside a build are stated as unsupported, as today.
- Mapping generations have a trigger: in production a generation lives for the process (restart after deploy); in development the engine re-checks the mtimes of Gemfile.lock, proscenium.json, `.proscenium/packages/*/package.json` and participating gems' package.json at most once per request and rebuilds the map and invalidates `BundledGems` and resolver caches on change. A Go-side test asserts the new context-map config key arrives (Go silently ignores unknown keys).
- Adoption is signalled by the committed workspace registration (`.proscenium/packages/*` in root `workspaces` or pnpm-workspace.yaml), not by the directory's existence, which Git drops when empty. This supersedes the DX requirement's marker. Tests cover zero-context adoption and removal of the last manifest gem.
- Dependency specs are validated against an allow-list: semver ranges, dist-tags, `npm:` aliases, https Git and tarball URLs, and the gemspec-backed cross-gem reference. `catalog:`, `portal:`, `patch:`, other `workspace:`, `file:` and `link:` are participation errors. After every install the CLI scans the native lock and fails (exit 5) if any `@rubygems/*` entry resolves to a registry tarball. Conformance fixtures run against a local request-logging registry so "no public registry, no `@rubygems/*` request" is asserted directly. codaset's migration removes the `@rubygems/proscenium-ui` dependency and the `.npmrc` scope line in one step.
- Workspace registration in a monorepo is written relative to the workspace root (for example `apps/web/.proscenium/packages/*`), with a C05 case for a nested Rails app.
- `--offline` means no dependency fetching by Bundler or the JS manager; Proscenium does not sandbox Gemfile evaluation, native-extension builds, manager plugins or permitted scripts, and the docs say a stronger guarantee needs external network isolation.
- Stage A adds source-package semantic regressions: for each field the projection drops (`browser`, `imports`, `exports`, self-reference, `bin`, scripts), the plan classifies it as preserved by the engine reading the original package.json or as an author-contract restriction, and a fixture per class proves the classification.
- Exact manager versions are pinned in the capability table for PR CI; a nightly canary runs each line's newest patch. All conformance rows run on one host per PR; release-gate rows run on every supported host. Re-estimating the effort after Stage A is a gate before Stage B.
- If the CLI stays in Go, all five CLI binaries build in one job with `GOOS`/`GOARCH` and `CGO_ENABLED=0`, and the plan specifies the behaviour when Proscenium itself is a Git or path source (no packaged binary): the launcher prints how to build it or falls back with a named error.
- Folding the accepted requirements into the body is a Stage A entry criterion, and the fold removes review-pipeline references (UC1-UC3, "the CEO requirement", "the Eng phase") from the body.
- Stage A records, per manager, whether a production install can exclude contexts of gems only in excluded groups (`pnpm --filter`, npm `--workspace`, Bun `--filter`); by default every committed context is installed, and the docs state that cost.
- UC1, accepted by the user at the final gate (D2, 2026-10-04): v1 is a time-boxed pnpm + Bun pilot. Stage A starts by hand-writing `.proscenium/packages/hue/package.json` in london, registering it, running pnpm and routing hue's bare imports through the context with the test-only seam; then codaset with proscenium-ui on Bun 1.4 or newer. The time box is set at Stage A start and recorded on #154 (reviewers suggested one to two weeks). Kill criterion: if a context cannot give hue its dependencies and one React instance in bundled and unbundled mode inside the time box, Stage A is NO-GO and the design reopens. npm is unsupported in v1 like Yarn: a project selecting npm (packageManager, package-lock.json or npm-shrinkwrap.json) gets the unsupported-manager error (exit 3) naming pnpm and Bun, and adding npm later is a new adapter with its own evidence. Supported lines narrow to the pnpm and Bun lines london, platform and codaset run plus one CI floor per manager; qualification hosts are the hosts those apps develop and deploy on, recorded in Stage A. The stable (non-experimental) bridge label for outside authors waits until at least one gem outside the maintainer's apps adopts it. This supersedes npm rows and npm lines throughout the body (support table, C07, C42, C44, C46, C47, Stage A order, final acceptance) and the CEO requirement's npm-specific wording.
- UC2, accepted by the user at the final gate (D3, 2026-10-04): the v1 command surface is `proscenium install`, `proscenium install --frozen`, `proscenium inspect` and `proscenium gem check`; `doctor`'s checks (undeclared imports, peer identity, stale contexts) run inside `install` and `inspect`. Deferred: `init`, `sync`, `lock`, `update`, `add`/`remove`, `migrate` (replaced by a written migration recipe in the guide), `clean`, the committed `bin/proscenium` launcher and its bootstrap, version handoff between Proscenium versions, transactional journals and the 100-gem performance gate. Developers run `bundle exec proscenium install`. Recovery from an interrupted install is re-running `install` (atomic context writes plus the OS lock make it idempotent); owned committed files are restored with git. This supersedes the DX requirements' `bin/proscenium` wording, `--restore`, journal resume and `init` diff preview (the preview moves to `install`, which prints first-run owned edits as a diff before writing), and the CEO requirements' `sync` behaviour; C34 asserts the re-run recovers and C48's three commands are `bundle add`, `bundle install`, `bundle exec proscenium install`.
- UC3, accepted by the user at the final gate (D4, 2026-10-04): the manager-independent dependency URL scheme with peer digests leaves v1 for its own issue. Stage C keeps today's real-path URL rule (`UrlPathFromFsPath`), with EvalSymlinks on the resolved file and serving of npm-shaped nested copies under `.proscenium/packages/<gem>/node_modules/` kept as accepted while any v1 linker can nest a conflicting version under a context (Stage A records whether Bun's hoisted linker does). C46 keeps correct per-manager resolution but drops "URLs identical across managers" and "no `.pnpm`/`.bun` segment"; C13's distinct peer variants are asserted through distinct real paths. The UC3-conditional requirements above (invalidation procedure, provenance-aware identity) move to the new issue.
- Eng re-run (2026-10-04), dependency allow-list correction: the allowed spellings are semver ranges, dist-tags, `npm:` aliases, `github:owner/repo` with an optional `#<ref>`, `git+https://` and `git+ssh://` URLs with an optional `#<ref>`, `https://` tarball URLs, and the gemspec-backed cross-gem reference. This supersedes the earlier list, which rejected the `github:` dependencies both pilot gems declare. The install summary lists every Git or URL dependency a gem introduces. Verified with `stage_a_hue_shape`.
- Peer checks distinguish sharing from provision. A peer must resolve to the same real file from the context and the app only when the app itself declares that package (sharing intended); an absent optional peer, a gem-backed peer and C13's intentionally distinct providers are checked against the native baseline instead. Stage A's first peer probe pins the app at a non-latest in-range version (for example react 18.2.0 against a `^18.0.0` peer) on every pnpm and Bun line and records whether any native setting makes the context share it; if none does, that is NO-GO under the kill criterion, not a documented `pnpm dedupe` step. The engine repeats the sharing check when it builds a mapping generation (Ruby realpath comparison), so an app-only `pnpm update react` that splits the peer is reported at the next build. This supersedes the earlier "every declared peer must equal the app's realpath" rule and its `pnpm dedupe` remedy.
- An install writes `.proscenium/installing` before it writes any context and removes it only after the native install and validation succeed. While it exists the engine refuses to build and names `bundle exec proscenium install` (re-running recovers). C34 builds after an interruption and before the retry. This replaces the protection the deferred journal gave; the OS lock still serialises installs.
- `install` requires the bundle to be installed already (`bundle install` after any Gemfile change, as `bundle exec` needs); if its Bundler phase changes the selected Proscenium version, it stops before generating contexts and tells the user to re-run. When Proscenium itself is a Git or path source with no packaged binary, `bundle exec proscenium install` fails with a named error giving the build command.
- The staleness hash is computed in one place, the Ruby side of `bundled_gems.rb`, over a fixed-field encoding (not `JSON.generate` output); the CLI calls the Ruby helper for it and writes it as an opaque string. Shared golden vectors cover key order, escapes, absent versus empty fields and every allowed `json` gem version.
- Real-path identity applies only when the pre-resolution path is under `node_modules/` or `.proscenium/packages/`; an app's own `link:`, `file:` and workspace-sibling packages keep today's paths. A regression for a `link:` dependency, a `file:` dependency and a pnpm workspace sibling (the `fixtures/dummy` cases) lands before any Stage C change. This narrows the earlier "applied the same way to the app's and every context's resolves" requirement.
- `inspect` resolves each participating gem's entry files through the engine's resolve-only path and reports external imports the gem does not declare; `install` prints them as warnings. A new conformance row covers a gem that imports an undeclared package.
- Fixtures are hermetic: proscenium-ui, hue-shape `github:` dependencies and React come from committed tarballs and a local bare Git repository (`file://`), served by the seeded request-logging registry; the read-only Bundler path is made writable again before cleanup (Windows).
- Root manifest and pnpm-workspace.yaml registration is a textual splice that preserves key order, indent, CRLF, comments and the trailing newline; golden tests cover tabs, four-space indent, CRLF, YAML comments and the `workspaces: {packages: []}` form.
- Bun support requires the text `bun.lock`; a project with only `bun.lockb` gets the unsupported-configuration error. Stage A's C09 asserts, per manager, that an edited context with a stale lock fails frozen mode, since Bun exits 0 when contexts are missing.
- The CI recipe gives a post-upgrade command for Dependabot and Renovate gem bumps (`bundle exec proscenium install` then commit `.proscenium/packages` and the lock), so the frozen check is not disabled.
- Deployment notes and a Stage C test cover a typical dotfile-deny proxy rule in front of Rails, which would block `/.proscenium/...` and `/node_modules/.pnpm/...` URLs.
- `Bundler.locked_gems` returning nil (no lockfile) is handled explicitly: the orphan check is skipped and the existing "No gems in your Gemfile" path applies.
- The pilot rejects a Rails app nested inside an enclosing JS workspace (unsupported-configuration error naming the layout), because dependency files would resolve outside `Rails.root` where the middleware cannot serve them and two apps could share one native lock. This supersedes the earlier monorepo registration requirement until a workspace-store mapping and a workspace-root lock are designed; Stage A records whether london, platform or codaset use such a layout.
- Mapping-generation triggers also cover the root workspace registration files (package.json `workspaces`, pnpm-workspace.yaml), native linker configuration (`.npmrc`, `bunfig.toml`) and a successful install; the Bun daemon's build cache key includes the mapping generation.
- The pilot GO subset is C04, C08, C12 and C13 (with the non-latest peer pin), C42, C43, C45 and C46's resolution part, on pnpm and Bun; the rest of Stage A's former list moves to Stage C and D gates. Folding the accepted requirements into the body is a hard Stage A entry gate owned by the maintainer.
- Stage A includes Bun's default trusted-dependencies list as a case: a gem that introduces a package on that list must not run its install script without the app's own approval.
- The development refresh path has a thread-safety test under Puma (the memoized `BundledGems` state is rebuilt while requests run).
- UC4, accepted by the user at the final gate (D5, 2026-10-04): participation is opt-in. A gem joins JS dependency installation only when its gemspec sets the metadata key `proscenium.dependencies` to `"true"` (the author opt-in; `proscenium.frontend_root` may still select the manifest directory) or the app sets `gemOverrides.<gem>.participate: true` in proscenium.json (the consumer opt-in for a gem whose author has not opted in). `participate: false` still excludes an opted-in gem. A gem that has not opted in never gets a context and keeps today's app-context lookup; if its package.json is invalid, `install` warns and skips it rather than failing. `inspect` lists gems that ship a root package.json but have not opted in, so an app can opt them in deliberately. hue and proscenium-ui add the gemspec metadata line (or london, platform and codaset opt them in) as part of the pilot. Evidence: `actiontext` 8.1.3.1, which every `rails` app installs, ships a root package.json declaring `@rails/activestorage` and a `trix` peer. This supersedes the maintainer requirement "a gem with a valid package manifest participates" and the CEO "participation is manifest-driven" requirement; the DX consumer escape keeps working through `participate: false`. Verified by a conformance row: an app bundling `actiontext` without opting it in gets no actiontext context and no extra npm packages; an opted-in gem with an invalid manifest still fails with a participation error.
- Eng pass 3 (2026-10-04), Bun linker: registering `.proscenium/packages/*` in a single-package Bun app can switch Bun from a hoisted `node_modules` to its isolated `.bun/` store, which moves every existing dependency and changes unbundled URLs, manifest keys and CSS/font URLs app-wide (measured on Bun 1.3.13: `node_modules/.bun/` appeared and the old tree moved to `node_modules/.old_modules-<hash>`; `[install] linker = "hoisted"` restored it). Because linker policy is never changed silently, `install` refuses to register a Bun app whose `bunfig.toml` does not set `[install] linker` explicitly, and the error explains both values and what each does to URLs. Stage A's first Bun probe repeats the measurement on Bun 1.4 against a copy of codaset's real `bun.lock`, `bunfig.toml` and `.npmrc`, then re-runs codaset's unbundled pages and the `bun test` harness after registration. The ignore rules cover `node_modules/.old_modules-*`. Under the hoisted linker, a participating gem's lookup must never take the legacy `node_modules/@rubygems/<gem>` branch (a test asserts it).
- v1 `install` has no Ruby phase: it requires an installed bundle, the Ruby helper fails naming `bundle install` if any locked spec is missing, and the body's Ruby-install, handoff, `--ruby-arg` and Bundler-environment-scrubbing text and the C37/C38 sub-cases that exist only for that phase are deleted. This supersedes the earlier "stop if the Proscenium version changes" requirement, which no longer has a phase to guard.
- Projection and hash have one owner: the Ruby helper (beside `bundled_gems.rb`) produces each context's bytes and its hash; the CLI only writes those bytes and drives the package managers. The context field is named `projectionSha256` (it hashes the projection, not the source manifest bytes). `PROSCENIUM_STALE_CONTEXT=warn` downgrades the engine's staleness error to a logged warning for an incident and is documented as a temporary escape.
- Cross-gem references are evaluated against the participating context set, not the locked universe: a required reference to a gem that is in the gemspec but has not opted in (or is excluded) is a participation error that says the target does not participate and how to opt it in, distinct from the missing-gemspec-dependency error; an optional peer is linked only when the target participates and is otherwise omitted.
- An opted-in gem whose selected manifest (root or `proscenium.frontend_root`) is missing or unreadable is a participation error, not a silent skip; only non-participating gems keep the no-manifest behaviour.
- `npm:` alias targets are normalized before either manager runs, and an alias that resolves to `@rubygems/*` is a participation error; a request-logging fixture covers it. The post-install lock scan stays as a second check.
- The engine checks `.proscenium/installing` on every build and resolve request, including before the Bun daemon returns a cached result; C34 warms both caches before interrupting an install.
- Bun's default trusted-dependencies list: a Bun app must declare an explicit `trustedDependencies` array in package.json (possibly empty) before registration, so Bun's default list does not apply to packages a gem introduces; Stage A verifies on each Bun line that an explicit array replaces the default list, and the case is in the pilot GO subset. If it does not, Bun registration is refused until another mechanism is proven.
- The install-time undeclared-import scan is dropped (it needed whole-graph traversal and an entry-file set the plan cannot define); the engine's named resolution-miss error for a participating gem covers the case at build time. This supersedes the Eng re-run's inspect/install undeclared-import requirement.
- Development refresh also watches path gems' gemspec files (participation metadata) and is throttled to at most one check per second per process; platform-variant qualification compares participation eligibility across variants; a transition test shows that withdrawing participation removes the committed context and its native lock entries on the next `install`.
- Every "nothing happened" assertion has a seeded positive control that must turn it red: an unrewritten `*` context reference for the no-registry check, a copied file for zero frontend writes, a write into a gem root, a boot-time Go call, and an app-root fallback for context-only lookup.
- Stage A peer probes run against copies of london's, platform's and codaset's real JS configuration (run locally like the hue leg; public fixtures reproduce the relevant settings), with `auto-install-peers=false` and `resolve-peers-from-workspace-root=false` variants, and assert that creating pnpm-workspace.yaml for london does not change how its `package.json#pnpm` settings are read.
- Deployment: a fixture covers Heroku-style buildpack order (Node first, Ruby first); `assets:precompile` is documented as the deploy-time drift gate and the engine's staleness error must fire there, not at the first request; the CI drift check runs with every Ruby group installed.
- Stage A includes a gem-introduced `github:` dependency with a `prepare` or `postinstall` script, which must not run without app approval on each line; an age-gate failure such as pnpm `minimumReleaseAge` names the gem context that introduced the package.
- The Stage A entry gate (folding the requirements into the body) is mechanical: a checklist script fails if the body still mentions UC1-UC4, "the CEO requirement", "the Eng phase", `map.json`, journals, `bin/proscenium`, or npm outside the unsupported-manager error; the pilot's conformance rows live in one table.
- Gate override (D7, 2026-10-04): the CLI is Ruby, not Go. After UC2 and Eng pass 3 the CLI computes nothing of its own: the Ruby helper produces every context's bytes and hash, pnpm and Bun own resolution and installation, and `install` has no Ruby phase. Every run already starts under `bundle exec` with Bundler loaded, so a Go binary would add a second Ruby and Bundler boot (about 0.3 s warm, measured in `fixtures/dummy`) and a cross-language protocol, and nothing v1 does needs Go's startup time. The shape:
  - `exe/proscenium` is the CLI, a Ruby executable declared in the gemspec (`spec.bindir = 'exe'`, `spec.executables = ['proscenium']`; neither exists today). It requires only `proscenium/bundled_gems` and new files under `lib/proscenium/cli/`, never `proscenium` itself (which loads ActiveSupport), Rails, FFI or the engine library. A test asserts that `ActiveSupport`, `Rails`, `FFI` and `Proscenium::Builder` are not loaded after each CLI command, with a seeded `require 'proscenium'` as its positive control.
  - The Ruby helper is an in-process library call: no helper subprocess, no JSON protocol between languages and no protocol-version mismatch error.
  - pnpm and Bun run through `Process.spawn` with argument arrays (no shell), an explicit `chdir`, environment overlays and streamed output; INT and TERM reach the child and the CLI waits for it, then maps its status to the plan's exit codes.
  - The project lock is `File#flock(File::LOCK_EX | File::LOCK_NB)` on `.proscenium/lock`; Windows qualification verifies the lock is released when the process is killed.
  - The CLI ships as Ruby files in every gem, platform and plain alike, so a Git or path source of Proscenium has the CLI with no build step. The plain-gem archive check is unchanged.
  - Performance: no Go startup budget. The measured gate is a warm no-op `bundle exec proscenium install` against the native `pnpm install` or `bun install` alone, reported as Ruby boot, Bundler load, projection and native install time.
  - Superseded: Motivation's "Go is the settled CLI language", the Go clauses of "Decision and product contract", the CLI contract's `cmd/proscenium/`, `CGO_ENABLED=0`, packaged-binary, launcher and Go subprocess paragraphs and the batched-helper JSON protocol, Stage B's binary packaging and startup gates, C37's binary cases and C40's direct-Go-startup case, the `cmd/proscenium/` and `internal/package_manager/` rows in Suggested repository changes, the packaged-Go-CLI clause of final acceptance, the earlier "five CLI binaries in one job" and "Git or path source has no packaged binary" requirements, the helper protocol-mismatch exit 3, and "the CLI calls the Ruby helper" in the hash and projection requirements (both are now in-process calls). Taste rows 30, 53, 76 and 79 are overridden. The fold checklist script also fails on `cmd/proscenium`, `CGO_ENABLED`, "Go CLI" and "packaged binary".
- Eng pass 4 (2026-10-04, after D7), project root: `--project` is dropped. The project is the active bundle's `Bundler.root`, so running from a subdirectory works and a `BUNDLE_GEMFILE` naming another app selects that app; contexts can never be generated from one app's bundle into another app's tree. Tested from a subdirectory and with `BUNDLE_GEMFILE` set.
- The project lock's file descriptor is passed to the pnpm or Bun child (`Process.spawn` redirect), so a manager that outlives a killed CLI keeps the lock: killing the CLI with SIGKILL and retrying at once exits 7 (busy) until the manager exits. Manager executables are resolved explicitly, including Windows `.cmd` shims through `PATHEXT`; Windows Ctrl-C delivery and lock release are qualified on windows-latest, not assumed from the Unix behaviour.
- The manager child's environment is built inside `Bundler.with_unbundled_env` (as `Rakefile` does for `gem build`), then native configuration overlays are applied, so a dependency lifecycle script that runs Ruby sees the same environment as a direct native install. A lifecycle fixture that runs `ruby -e` compares the two.
- The pass-3 rule that the helper "fails naming `bundle install` if any locked spec is missing" is replaced: `bundle exec` already guarantees the active bundle is installed, and gems outside it (excluded groups, other platform variants) follow the production rule (committed context trusted, skip reported). One test covers an excluded group and a non-host platform variant together.
- `gemOverrides.<gem>.name` is dropped from v1: no known gem needs a renamed context, and an overridden name would sit outside the `@rubygems/*` alias and lock-scan protections. A gem whose name is not a valid npm package name gets a participation error naming it; C27's uppercase case asserts that error. This supersedes the DX requirement listing `name` as a `gemOverrides` key and the body's "Explicit name overrides are recorded and validated against collisions".
- Release verification runs the installed CLI in a clean process: `bin/verify-installed-gem` runs the installed `exe/proscenium --version` from the platform and plain archives and asserts that ActiveSupport, Rails, FFI and `Proscenium::Builder` are not loaded; CLI tests use their own helper that does not boot the dummy Rails app (today's `test/test_helper.rb` loads `fixtures/dummy/config/environment`). `proscenium gem check` runs without a bundle, loading the gemspec with `Gem::Specification.load`, so a gem author can run it after `gem install proscenium`.
<!-- /autoplan-accepted:eng -->

#### Eng dual voices

Claude SUBAGENT (eng — independent review), in-host, INPUT hash `9d65374a...` matched, ran probes against a local request-logging registry (pnpm 10.34.4, npm 11.19.1, Bun 1.3.13 with a non-dot directory): F1 HIGH pnpm silently splits the shared peer after the app bumps it (verified); F2 HIGH `--frozen --production` needs excluded-group sources; F3 HIGH Go orchestrator buys little (same as CEO P2); F4 HIGH cut the URL scheme, canonicalize the resolved file; F5 MED-HIGH raw-byte hash false positives and CRLF; F6 MED OS file lock, cut the journal; F7 MED-HIGH spec allow-list, `@rubygems/*` lock scan, codaset migration order; F8 MED pin CI versions, tier the matrix, estimate low; F9 MED no generation trigger, silent config-key typo; F10 MED monorepo registration path; F11 LOW plan hygiene.

Codex SAYS (eng — architecture challenge), gpt-6.1-sol, completed: P1 resolver change misses the bare-with-extension shortcut (`bundless.go:345`), CSS/SVG resolve (`bundless.go:46`) and mixins (`mixins.go:60`); P1 realpathing the resolve dir does not establish identity; P1 URL scheme identity can collide (and `.proscenium` is outside `ALLOWED_DIRECTORIES`, `lib/proscenium.rb:18`); P1 no refresh contract for boot-time state; P1 journal check is not build/install isolation; P2 `--offline` overclaims; P2 directory existence is not a durable adoption marker; P2 Stage A cannot see semantics lost in projection. All four cited code locations verified.

```
ENG DUAL VOICES — CONSENSUS TABLE:
  Dimension                           Claude  Codex  Consensus
  1. Architecture sound?               core yes, gaps  core yes, gaps  CONFIRMED (resolver seam, identity, refresh)
  2. Test coverage sufficient?         no      no      CONFIRMED (peer bump, semantic regressions, overlap)
  3. Performance risks addressed?      minor   not raised  N/A (single voice: hash cost measured ~31 ms)
  4. Security threats covered?         gaps    gaps    CONFIRMED (spec allow-list, lock scan; offline overclaim)
  5. Error paths handled?              gaps    gaps    CONFIRMED (frozen production, refresh, adoption, isolation)
  6. Deployment risk manageable?       gaps    gaps    CONFIRMED (Docker frozen path; adoption durability)
```
Cross-phase themes reinforced: UC3 (both Eng voices recommend deferring the URL scheme), UC1/UC2 (Codex repeats the pilot; Claude repeats the Go-orchestrator cost). Single-voice: F5, F6, F8, F10 (Claude), Codex 6 (offline). None critical.

#### Eng review sections

**Section 1, Architecture.**
```
                         Gemfile.lock ─────────────┐
                              │                    │ Bundler.locked_gems (orphan/excluded test)
   bin/proscenium ──> CLI (Go, CGO off) ──> Ruby helper ─┐   (shares lib/proscenium/bundled_gems.rb)
        │   OS lock .proscenium/lock          │          │
        │                                     v          v
        │        projection + allow-list ─> .proscenium/packages/<gem>/package.json (committed,
        │                                     │            canonical-hash + description fields)
        └──> native npm/pnpm/Bun install ─────┴─> node_modules, .proscenium/packages/*/node_modules
                 │ post-install: peer realpath check, @rubygems/* lock scan
                 v
 Rails boot / dev request ──> BundledGems (paths + locked names + context map, mtime-refreshed in dev)
                 │                    │ adoption = committed workspace registration
                 v                    v
   FFI config (builder.rb) ── Bun daemon config (runtime/server.rb:235) ── Go engine
                                        │
          one issuer-aware lookup: bundler.go branch, bundless chain, bundless:345 shortcut,
          bundless:46 CSS/SVG, mixins.go:60 ──> resolve from context dir ──> EvalSymlinks(result)
                                        │
                     URL: existing real-path rule (+ .proscenium/packages/*/node_modules serving)
```
Findings and dispositions: Codex 1 [P1] (confidence 9/10, `internal/plugin/bundless.go:345` `result.Path = "/node_modules/" + result.Path`) accepted; Codex 2 / Claude F4 [P1] (9/10, `bundless.go:80` realpaths `args.ResolveDir` only) accepted; Codex 3 [P1] (9/10, `lib/proscenium.rb:18` `ALLOWED_DIRECTORIES = 'app,lib,config,node_modules'`) accepted; Codex 4 / Claude F9 [P1] (9/10, `bundled_gems.rb:8` `@paths ||=`) accepted; Codex 7 [P2] (8/10, Git does not track empty directories) accepted; Claude F10 [P2] (7/10, monorepo glob root) accepted. Coupling added: the engine now reads committed files and Gemfile.lock at boot; justified by fresh-checkout correctness. Single points of failure: the Ruby helper protocol (versioned, exit 3) and Bundler. Rollback unchanged from CEO Section 1.

**Section 2, Code quality.** The one-reader rule (row 45) keeps Bundler access in `bundled_gems.rb` for both the engine and the helper; two readers would drift on excluded groups. Projection logic lives once, in the CLI; the engine only hashes canonical projected fields, which needs a Ruby canonicalizer: that is a second implementation of "which fields are projected", flagged as debt with a shared fixture that both sides must hash identically (accepted, row 51). Registry validation is ported, not duplicated. Over-engineering findings (journal, URL scheme, launcher handoff) sit in UC2/UC3 and taste row 52. No other issues.

**Section 3, Test review.** Framework: Minitest/Maxitest (`bin/test`), Ginkgo/Gomega (`go test ./test ./internal/...`), `bun test` in `fixtures/dummy` (AGENTS.md "Testing"). No code exists yet, so every path below is a planned requirement.
```
CODE PATHS (planned)                                     USER FLOWS
[+] CLI install pipeline                                 [+] First run (C48)
  ├── manager selection          [GAP→C07]                 ├── [GAP] [→E2E] rails new → install → render
  ├── helper query / version     [GAP] exit 3 skew         └── [GAP] no-manager case needs --manager
  ├── projection + allow-list    [GAP] catalog:/portal:/patch:
  ├── context write / orphan     [GAP→C36 new case]       [+] Teammate bumps gem
  ├── native install             [→E2E C02/C45]              └── [GAP] [→E2E] engine names stale gem
  ├── peer realpath check        [GAP] bump after lock    [+] Dev edits path gem manifest
  └── @rubygems lock scan        [GAP] exit 5                 └── [GAP] [→E2E] map refresh in same process
[+] Engine boot map                                       [+] Deploy
  ├── adoption via registration  [GAP] zero-context            ├── [GAP] [→E2E] frozen --production --offline
  ├── orphan vs excluded group   [GAP→C32 new case]           └── [GAP] Docker layering
  ├── canonical hash             [GAP] CRLF, scripts-only edit [+] Error states
  └── dev mtime refresh          [GAP]                         ├── [GAP] interrupted install message
[+] Engine lookup                                              ├── [GAP] consumer escape printed
  ├── bundler.go branch          [GAP→C04]                     └── [GAP] Yarn / un-adopted notice
  ├── bundless chain             [GAP→C46]
  ├── bundless:345 shortcut      [GAP] new
  ├── CSS/SVG + mixins           [GAP] new
  └── EvalSymlinks(result)       [GAP] [→E2E] unbundled identity
EXISTING TO KEEP GREEN: test/rubygems_test.go, gem stylesheet imports, nested-gem-root and prefix cases (683dc375, c9cb03c8), Bun harness (C24)
COVERAGE: 0/30 planned paths have tests (no code yet) | GAPS: 30, 9 E2E
```
Regression rule: existing `@rubygems` resolution (non-participating gems keep both chains unchanged) is a critical regression contract, already approved in the CEO requirement ("Non-participating gems keep both chains unchanged"); carried forward. Test plan artifact written: `~/.gstack/projects/joelmoss-proscenium/joelmoss-docs-154-plan-review-eng-review-test-plan-20261004-001804.md`. Tests to retire: registry controller tests (ported first).

**Section 4, Performance.** Boot: one SHA over a canonical serialization per participating gem plus a YAML/JSON read of the registration; measured parse cost ~31 ms for 184 manifests, so single-digit milliseconds for known apps. Development refresh: four mtime stats per request at most, no hashing unless an mtime changed. CLI: one Ruby helper process per install; no per-gem Ruby. The 100-gem p95 target stays as written pending UC2. No N+1, DB or unbounded cache issues. No issues beyond those recorded.

Failure modes registry (Eng additions to the CEO registry):
```
 CODEPATH                    | FAILURE MODE                          | RESCUED? | TEST?   | USER SEES?               | LOGGED?
 ----------------------------|---------------------------------------|----------|---------|--------------------------|--------
 pnpm reinstall after bump   | context keeps old peer, two Reacts    | Y (new)  | C12/C13 | install error, dedupe fix| event
 bare-with-extension import  | resolves app's version, not gem's     | Y (new)  | new row | correct version          | debug
 mixin from participating gem| resolves from app root                | Y (new)  | new row | correct mixin            | debug
 npm nested copy URL         | 404 (path not allowed)                | Y (new)  | C21/C22 | asset loads              | no
 frozen production deploy    | needs excluded-group sources/network  | Y (new)  | C32     | skip reported            | event
 empty packages dir on clone | silently un-adopted                   | Y (new)  | new row | adoption kept            | no
 dev server across install   | stale map until restart               | Y (new)  | new row | map refreshes            | debug
 @rubygems/* from registry   | dependency confusion                  | Y (new)  | lock scan| exit 5                  | event
```
Critical gaps: 0 (every new row now has a rescue and a test requirement).

NOT in scope (Eng): building the CLI or engine changes (this is a spec review); new test framework; Windows qualification details beyond the plan's Stage D; sandboxing native scripts for a strict offline guarantee.

What already exists (Eng): see Step 0; reuse `bundled_gems.rb`, the two plugin chains, `UrlPathFromFsPath`, `ALLOWED_DIRECTORIES`, both config sites, Rakefile `PLATFORMS`, `bin/verify-installed-gem`, registry validation cases.

Parallelization (for implementation after Stage A):

| Step | Modules touched | Depends on |
|------|----------------|------------|
| Stage A proof | test/package_manager/stage_a, internal/plugin (seam) | — |
| Engine lookup + identity | internal/plugin, internal/css, internal/utils, lib/proscenium | Stage A |
| Ruby boot map + helper | lib/proscenium (bundled_gems, builder, runtime) | Stage A |
| CLI | cmd/proscenium, internal/package_manager | Ruby helper protocol |
| Packaging | Rakefile, gemspec, .github/workflows | CLI |
| Docs and migration | README, docs/guides | CLI + engine |

Lane A: engine lookup + identity (internal/). Lane B: Ruby boot map + helper (lib/proscenium/), then CLI, then packaging. Conflict flag: `lib/proscenium/builder.rb` config keys are shared by both lanes; land the config key first. Execution: Stage A, then A + B in parallel, merge, then docs/migration.

Eng Implementation Tasks:
- [ ] **T9 (P1, human: ~3h / CC: ~20min)** — plan — Specify the single issuer-aware lookup across all five resolve paths and EvalSymlinks on the result.
  - Surfaced by: Codex 1-2, Claude F4
  - Files: docs/plans/154-package-manager.md
  - Verify: each path named with its conflicting-version fixture
- [ ] **T10 (P1, human: ~1d / CC: ~1h)** — tests — Add the peer-bump-after-lock step to C12/C13 and the post-install peer realpath check.
  - Surfaced by: Claude F1 (probe)
  - Files: docs/plans/154-package-manager.md, test/package_manager/ (to be determined)
  - Verify: pnpm fixture fails install until `pnpm dedupe`
- [ ] **T11 (P1, human: ~2h / CC: ~15min)** — plan — Frozen production skip rule, adoption via registration, dev refresh trigger, canonical hash.
  - Surfaced by: Claude F2/F5/F9, Codex 4/7
  - Files: docs/plans/154-package-manager.md
  - Verify: C32 no-network, zero-context adoption, same-process refresh rows exist
- [ ] **T12 (P2, human: ~2h / CC: ~15min)** — security — Dependency-spec allow-list, `@rubygems/*` lock scan, local logging registry for fixtures.
  - Surfaced by: Claude F7
  - Files: docs/plans/154-package-manager.md
  - Verify: allow-list table and exit-5 row present
- [ ] **T13 (P2, human: ~1h / CC: ~10min)** — CI — Pin manager versions, nightly canary, tiered matrix, re-estimate gate.
  - Surfaced by: Claude F8
  - Files: docs/plans/154-package-manager.md, .github/workflows/main.yml (later)
  - Verify: capability table lists exact versions

Eng completion summary:
- Step 0: Scope Challenge — scope accepted as-is (cuts are UC1-UC3 for the user)
- Architecture Review: 6 issues found
- Code Quality Review: 1 issue found (projected-field list implemented twice; shared fixture)
- Test Review: diagram produced, 30 planned-path gaps identified (no code yet), test plan written
- Performance Review: 0 issues found
- NOT in scope: written
- What already exists: written
- TODOS.md updates: 2 items (from CEO), 0 new from Eng
- Failure modes: 0 critical gaps flagged
- Unresolved decisions: 3 (UC1-UC3, gate)
- Outside voice: codex completed
- Parallelization: 2 lanes, 2 parallel / 4 sequential steps
- Lake Score: N/A (no coverage-scored questions)

Approval readiness: PASS for Eng rows 45-53 (autoplan auto-decisions); taste rows 52-53 provisional; UC1-UC3 pending.

#### Final gate, round 1 (2026-10-04)

The user chose "Resolve challenges" (D1) and accepted UC1 (D2), UC2 (D3) and UC3 (D4). Decisions logged to the gstack decision log. Deferred work added to TODOS.md: npm adapter, deferred commands, manager-independent dependency URLs. Per autoplan, Eng re-ran on the amended plan.

#### Eng re-run (Phase 3, second invocation)

Methodology byte-identical to the first Eng run (`cmp`), re-read in full. Amendment checkpoint `autoplan-eng-aFNSpF`; voice snapshot `autoplan-eng-aXiwPu` (includes UC1-UC3).

Claude SUBAGENT (eng — independent review), in-host, INPUT hash `f316dce8...` matched: 1 HIGH manifest-driven participation enrols any gem with a root package.json (verified in this bundle: `actiontext` 8.1.3.1, which every `rails` app installs, declares `@rails/activestorage` and a `trix` peer); 2 HIGH peer sharing detected but not guaranteed, Layout-probe React row non-discriminating, `pnpm dedupe` unproven, no runtime check after `pnpm update react`; 3 HIGH projection hash in two languages; 4 MED-HIGH Go CLI unjustified after UC2 (taste); 5 HIGH blanket EvalSymlinks regresses `link:`/`file:` app packages; 6 MED-HIGH allow-list rejects `github:`; 7 MED no undeclared-import check; 8 MED non-hermetic fixtures; 9 MED manifest-editing fidelity; 10 MED Bun frozen detection and `bun.lockb`; 11 MED Dependabot/Renovate recipe; 12 LOW-MED dotfile-deny proxies; 13 LOW-MED `Bundler.locked_gems` nil (verified, Bundler 4.0.7); 14 process: fold gate, pilot GO subset.

Codex SAYS (eng — architecture challenge), gpt-6.1-sol, completed: P1 dropping journals lets a failed install leave matching contexts with an old graph; P1 blanket peer equality contradicts optional and distinct-provider peers; P1 handoff deferral needs a bundle prerequisite and version-change stop; P1 allow-list rejects both pilot gems' `github:` dependencies; P2 nested monorepo dependency files resolve outside `Rails.root` (`utils.go:379`, `middleware/base.rb:69`); P2 lock ownership undefined for shared workspaces; P2 generation triggers miss registration, linker config and the Bun daemon cache (`runtime/server.rb:502`).

```
ENG RE-RUN DUAL VOICES — CONSENSUS TABLE:
  Dimension                           Claude  Codex  Consensus
  1. Architecture sound?               gaps    gaps    CONFIRMED (peer policy, failed-install marker, nested layout)
  2. Test coverage sufficient?         gaps    gaps    CONFIRMED (non-latest peer pin, interruption-before-retry)
  3. Performance risks addressed?      ok      not raised  N/A
  4. Security threats covered?         gaps    gaps    CONFIRMED (allow-list spellings, URL deps visibility)
  5. Error paths handled?              gaps    gaps    CONFIRMED (bundle prerequisite, locked_gems nil, refresh triggers)
  6. Deployment risk manageable?       gaps    gaps    CONFIRMED (dotfile-deny proxies; monorepo layout)
```
New user challenge (both models across phases agree; changes a maintainer requirement): **UC4, participation is opt-in.** Codex (CEO phase, finding 5) asked for an author participation signal; Claude (Eng re-run, finding 1) found that `actiontext`, a dependency of the `rails` gem itself, ships a root package.json, so the current rule enrols Rails' own gems in every app and one bad third-party manifest fails every install. Queued for the gate; the maintainer requirement "a gem with a valid package manifest participates" stands until answered. Taste row 32 is superseded by UC4.

Eng re-run sections (focused on what changed):

**Architecture.** Participation boundary (UC4 pending), failed-install marker, peer policy split into sharing versus provision, nested-layout rejection and Ruby-only staleness hash all accepted. Updated flow:
```
 bundle install ──> bundle exec proscenium install
      │                 │ OS lock; write .proscenium/installing
      │                 │ Ruby helper: specs, locked names, projection hash (fixed-field)
      │                 │ allow-list (github:, git+https/ssh, https tarball, npm:, semver, tags)
      │                 v
      │        .proscenium/packages/<gem>/package.json (committed)
      │                 │ native pnpm / bun install (text bun.lock only)
      │                 │ sharing check (app-declared peers), @rubygems lock scan, undeclared-import report
      │                 v remove .proscenium/installing
 Rails boot / dev request: registration present? -> adopted; installing marker? -> refuse;
   hash/orphan/stale -> error; sharing re-check; generation keyed on lock, registration, linker config
 Engine: one lookup over five paths; EvalSymlinks only under node_modules/ or .proscenium/packages/;
   real-path URLs (UC3); nested-in-workspace apps rejected
```
**Code quality.** One implementation of the projection hash (Ruby) removes the two-language risk; registration edits are textual splices. No other issues.
**Tests.** New or changed rows: non-latest peer pin on pnpm and Bun; build after interruption before retry; `link:`/`file:`/workspace-sibling regression before Stage C; undeclared-import row; edited-context-stale-lock frozen row per manager; `bun.lockb` rejection; nested-layout rejection; Bun trusted-dependencies case; Puma refresh thread-safety; allow-list spellings with `stage_a_hue_shape`; hermetic fixtures. Test plan artifact updated (`...-eng-review-test-plan-<second datetime>.md`).
**Performance.** Sharing re-check per generation is a few realpath calls; no issues.

Failure modes added: failed install leaving old graph (rescued by marker, C34); app-only peer bump splitting React (rescued by generation re-check); `github:` dependency rejected (fixed by allow-list); Rails-gem auto-participation (pending UC4, otherwise every app is affected: CRITICAL if UC4 is rejected without the warn-and-skip fallback). Critical gaps: 0 accepted, 1 conditional on UC4.

Eng re-run tasks: T14 (P1) specify opt-in or fallback per UC4 answer; T15 (P1) peer sharing policy and non-latest pin probe; T16 (P1) failed-install marker and bundle prerequisite; T17 (P1) allow-list spellings and hermetic fixtures; T18 (P2) Ruby-only hash with golden vectors; T19 (P2) narrowed EvalSymlinks with `link:`/`file:` regression; T20 (P2) undeclared-import report; T21 (P2) textual manifest splice, `bun.lockb` rejection, nested-layout rejection, refresh triggers.

Eng re-run completion summary: Scope Challenge — scope accepted as-is (UC1-UC3 already applied); Architecture 6 issues; Code Quality 1; Test Review diagram updated, 11 gaps; Performance 0; failure modes 0 critical accepted, 1 conditional on UC4; unresolved decisions 1 (UC4); outside voice codex completed; parallelization unchanged (2 lanes).

#### Final gate, round 2 (2026-10-04)

The user accepted UC4 (D5): participation is opt-in. Taste choices shown at the gate (rows 7, 30/53/76, 31, 33, 43) stay as auto-decided unless overridden. Per autoplan, Eng re-runs on the amended plan before the gate is presented again.

#### Eng pass 3 (after UC4)

Methodology byte-identical (`cmp`), re-read. Voice snapshot `autoplan-eng-jEVNOU` (includes UC4).

Claude SUBAGENT (eng — independent review), INPUT hash `fe9f9712...` matched; read the three pilot apps' real configs and measured Bun 1.3.13: 1 HIGH registering workspaces flipped a hoisted Bun app to the isolated `.bun/` store (old tree moved to `.old_modules-<hash>`), which would change codaset's URLs; 2 HIGH the body plus ~80 superseding bullets contradict each other (npm, Stage A gate, `map.json`, deferred commands, manifest-driven participation); 3 MED-HIGH `install`'s Ruby phase is meaningless under `bundle exec`; 4 MED-HIGH projection in two languages, need one owner and a kill switch; 5 MED Go rationale gone after UC2 (taste); 6 MED cross-gem refs, C33, `gemOverrides.name`, receipt have no consumer (taste); 7 MED positive controls for negative assertions; 8 MED peer sharing depends on real pilot configs; 9 MED Heroku deploy order; 10 LOW-MED Git-dependency lifecycle scripts, `minimumReleaseAge`, CI groups; 11 LOW throttle mtime checks.

Codex SAYS (eng — architecture challenge), completed: P1 UC4 breaks the cross-gem guarantee (targets may not participate); P1 opted-in gem with missing manifest silently skipped; P1 `npm:` aliases bypass the `@rubygems/*` boundary; P1 installing marker not checked by persistent generations or the Bun daemon cache (`runtime/server.rb:502`); P1 Bun default script trust cannot be enforced by delegation; P2 undeclared-import scan needs traversal `resolve-only` lacks (`resolve.go:169`); P2 gemspec metadata changes missing from refresh and variant checks.

```
ENG PASS 3 DUAL VOICES — CONSENSUS TABLE:
  Dimension                           Claude  Codex  Consensus
  1. Architecture sound?               gaps    gaps    CONFIRMED (Bun linker, projection owner, eligibility set)
  2. Test coverage sufficient?         gaps    gaps    CONFIRMED (positive controls, cache-warm interruption, transitions)
  3. Performance risks addressed?      minor   not raised  N/A
  4. Security threats covered?         gaps    gaps    CONFIRMED (alias bypass, script trust, Git lifecycle)
  5. Error paths handled?              gaps    gaps    CONFIRMED (missing manifest, marker, kill switch)
  6. Deployment risk manageable?       gaps    gaps    CONFIRMED (Heroku order, Bun linker flip)
```
No new user challenge: the two voices do not agree on any change to the user's direction. Taste carried to the gate: Go CLI (Claude, fourth time; row 79) and cutting cross-gem references, C33 and the receipt from v1 (Claude only; recommend keeping, since D1's cross-gem rule is a settled user decision; row 80).

Sections (changes only). Architecture: projection and hash move to the Ruby helper; `install` loses its Ruby phase; Bun registration requires an explicit linker and trusted-dependencies list. Code quality: one projection implementation. Tests: positive controls, Bun linker before/after on codaset's config, cache-warm C34, participation transitions, alias fixture, Heroku order, real-config peer probes. Performance: throttled dev refresh. Failure modes added and rescued: Bun linker flip (refused without explicit linker), alias to `@rubygems/*` (rejected pre-install), opted-in missing manifest (error), stale cached Bun daemon result during install (marker check). Critical gaps: 0.

Eng pass 3 completion summary: scope accepted as-is; Architecture 4 issues, Code Quality 1, Tests 6 gaps, Performance 1; failure modes 0 critical; unresolved decisions 0 (taste rows 79-80 provisional); outside voice codex completed.

#### Final gate, round 3 (2026-10-04)

The user interrogated the CLI's role ("So the CLI is actually just going to be a wrapper?"), then overrode the Go CLI taste choice (D7): the CLI is Ruby. The override is recorded as an accepted Eng requirement and decision row 81. Per autoplan, Eng re-runs once more on the amended plan (the third and last revise cycle) before the gate is presented again.

#### Eng pass 4 (after D7, Ruby CLI)

Methodology byte-identical (`cmp`), re-read in full. Voice snapshot `autoplan-eng-dOWLRa` (INPUT `e86bcdc1...`, includes D7).

Claude SUBAGENT (eng — independent review): unavailable. The autoplan phase guard denied the dispatch three times with "Native parent evidence has not reached the journal yet". Cause, verified by running the hook against this session's journal: its transcript reader stops at the session's compact boundary (2026-10-03T23:56:43Z), so no post-compaction tool call is ever visible to it. Degradation rule applied: this pass is `[codex-only]`, with no confirmed consensus.

Codex SAYS (eng — architecture challenge), completed: P1 `--project` can pair one app's files with another app's active bundle; P1 releasing the CLI's `flock` does not prove a surviving pnpm/Bun child has stopped, and Windows shim/console handling is unspecified; P2 Bundler's environment leaks into dependency lifecycle scripts (repo precedent `Rakefile` `with_unbundled_env`); P1 "fails if any locked spec is missing" contradicts the production rule and non-host platform variants; P2 `gemOverrides.name` escapes the `@rubygems/*` protections; P2 release verification has no installed-CLI gate (`bin/verify-installed-gem` tests only the engine library; `test/test_helper.rb` boots Rails). Recommendation: revise before Stage A. All six were checked against the cited files and accepted (row 82; the `name` override was cut rather than extended, row 83).

```
ENG PASS 4 DUAL VOICES — CONSENSUS TABLE [codex-only]:
  Dimension                           Claude  Codex  Consensus
  1. Architecture sound?               N/A     gaps    N/A (native voice unavailable)
  2. Test coverage sufficient?         N/A     gaps    N/A
  3. Performance risks addressed?      N/A     not raised  N/A
  4. Security threats covered?         N/A     gaps    N/A
  5. Error paths handled?              N/A     gaps    N/A
  6. Deployment risk manageable?       N/A     gaps    N/A
```

Sections (changes only). Architecture: the CLI is `exe/proscenium` running in-process under `bundle exec`; the project is `Bundler.root`; pnpm/Bun run as children holding the lock descriptor, in an unbundled environment. Code quality: one Ruby reader of Bundler for engine and CLI; no cross-language protocol. Tests: subdirectory and `BUNDLE_GEMFILE` invocation, SIGKILL-then-retry, lifecycle environment parity, excluded group plus non-host variant, uppercase gem name, installed-CLI clean-process check. Performance: the no-op gate is `bundle exec proscenium install` against the bare native install. Failure modes added and handled: wrong-bundle generation (impossible by construction), overlapping installer after a killed CLI (lock held by the child), Bundler-polluted lifecycle scripts (unbundled env). Critical gaps: 0.

Eng pass 4 completion summary: scope accepted as-is; Architecture 3 issues, Code Quality 1, Tests 3 gaps, Performance 0; failure modes 0 critical; unresolved decisions 0; outside voice codex completed; native voice unavailable (phase guard cannot read past compaction).

#### Final gate, round 4 (2026-10-04): APPROVED

The user approved the plan as reviewed (D8). All three revise cycles were used (D1/UC1-UC3, D5/UC4, D7/Ruby CLI). Open taste rows stay as auto-decided: 7, 31, 33, 43, 80 and 83. The first P1 task is folding every accepted requirement into the body (T2), gated by the checklist script; then the london hue pilot (T1).

#### Body fold (T2), 2026-10-04

Every accepted requirement above (24 CEO, 21 DX, 65 Eng, including the D7 Ruby CLI override) is folded into the body, and the trailing accepted-requirements list is gone from it; the `autoplan-accepted` blocks above stay as history. The CLI sections are rewritten for the Ruby CLI. The conformance matrix gains a Gate column (the pilot GO subset is every row gated A) and rows C49-C55; C38 is marked deferred. `bin/check-154-plan` is the Stage A entry gate: it fails on review-pipeline labels, superseded text and npm outside the unsupported-manager error, and requires one conformance table with a Gate column. Judgments the fold made where the accepted text left a gap: `proscenium.json` loses its `bridge.*` keys (the context directory is owned and fixed), `.proscenium/state.json` is dropped (no reader once engine-read state and transactional recovery left v1), C47's app-side report is dropped for the same traversal reason as the gem-side scan, the pre-adoption notice names opted-in gems, a context for an installed gem that withdrew participation is stale, and platform-variant comparison runs only where variant sources are cached.

#### No time box, 2026-10-04

After the fold the maintainer removed the Stage A time box (row 84). Stage A ends on evidence, not a date: the kill criterion and the NO-GO rules are unchanged, minus their deadline, and the entry gate is `bin/check-154-plan` alone. The rest of UC1 stands.

#### pnpm 10 dropped, 2026-10-04

During Stage B the maintainer dropped pnpm 10 (row 85). Stage A showed it is the only line that leaves a gem's context on an older copy of a shared peer after the app upgrades it; the alternative was `install` running `pnpm dedupe` on a found split. The capability table starts at pnpm 11, CI's floor is 11.28.4, and london and platform, both on pnpm 10, move to 11 before adopting: on 11, london's install stops for unapproved build scripts (esbuild, msw) and platform's for its Git dependencies (`ERR_PNPM_EXOTIC_SUBDEP`). pnpm 11 also stops reading the `pnpm` field in package.json (it warns and ignores it, measured on 11.28.4), so platform's `pnpm.overrides` pinning react and react-dom to 18.2.0 must move to its pnpm-workspace.yaml, or the upgrade silently drops the pin.

