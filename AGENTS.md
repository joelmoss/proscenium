# AGENTS.md

This file provides guidance to coding agents (Claude Code, Codex and others) when working with code in this repository.

## Project Overview

Proscenium is a Rails engine that provides real-time frontend asset bundling and minification using esbuild. It processes JavaScript, TypeScript, JSX, TSX, and CSS files on-demand with zero configuration and no build step.

## Prerequisites

- Ruby >= 3.4.0 (project uses 3.4.8)
- Go 1.25+
- Rails 7.2 to 8.x

## Architecture

The project is a hybrid Ruby gem + Go shared library:

- **Ruby (lib/proscenium/)**: Rails integration, middleware, helpers, side-loading logic
- **Go (internal/)**: Core bundling/compilation via esbuild, exposed as a C shared library via FFI

### Key Components

- `lib/proscenium/builder.rb` - FFI interface to Go binary, handles build/resolve/compile operations
- `lib/proscenium/railtie.rb` - Rails engine configuration and middleware setup
- `lib/proscenium/middleware.rb` - Rack middleware that intercepts asset requests
- `lib/proscenium/side_load.rb` - Auto-loads JS/CSS alongside views, partials, layouts
- `lib/proscenium/importer.rb` - Tracks imported assets for inclusion in HTML
- `lib/proscenium/monkey.rb` - The ActionView hooks side loading runs through, prepended in `railtie.rb`: `Base#_run`, `TemplateRenderer#render_template`, `PartialRenderer#render_partial_template` and `CollectionRenderer#render_collection`
- `lib/proscenium/helper.rb` - View helpers included into ActionView: `sideload_assets`, `include_assets`/`include_stylesheets`/`include_javascripts`, `css_module`, and `proscenium_render_block_partial`, which `monkey.rb` calls for a partial rendered with a block
- `main.go` - C-exported functions (`build_to_string`, `resolve`, `compile`, `free_cstr`, `reset_config`) called from Ruby
- `internal/builder/` - esbuild configuration and build orchestration
- `internal/plugin/` - Custom esbuild plugins (CSS modules, SVG, i18n, RJS, etc.)
- `exe/proscenium` and `lib/proscenium/cli/` - The `proscenium` CLI for gem dependency contexts
  (#154): `install`, `install --frozen`, `inspect` (also `doctor`) and `gem check`. Every error
  is a code in `cli/error.rb`'s catalog, pinned by a golden in `test/cli/golden/`
  (`GOLDEN=update bin/test test/cli/errors_test.rb` rewrites them); `cli/reporter.rb` lays out
  and colours human output, and `--json` keeps a stable event shape. The supported pnpm and Bun
  lines are `cli/capabilities.json`
- `lib/proscenium/context_map.rb`, `stale_contexts.rb`, `mapping_generation.rb` - The engine side
  of #154: which gems map to a committed context under `.proscenium/packages/`, the refusal to
  build while one is stale, and the development-time check for files that changed
- `lib/proscenium/runtime/` - The `bun test` harness: a `rails runner` daemon (`server.rb`) over a Unix socket, plus the Bun plugin (`bun.js`) and its bootstrap (`bootstrap.js`)

### Backlog and audits

- `TODOS.md` - The backlog: open items grouped by area, each with What / Why / Context and, for
  most, a `**Priority:**` line (P3, P4). Finished items move to `## Done`.
- `docs/AUDIT.md` - Two read-only simplification audits (2026-09-08: `F-<AREA>-<N>`; 2026-10-01:
  `F2-<AREA>-<N>`, `H-<N>`, `BL-<N>`, `Q-<N>`). Read the header's precedence rules and the
  Progress table first: that table is the current status of every finding, and a finding's own
  write-up further down is a dated snapshot whose described symptoms later work may have corrected.

## Code Style

- All Ruby files must be styled as per RuboCop.

## Development Commands

### Compile Go binary (required before running tests)
```bash
bundle exec rake compile:local
```

### Run Ruby tests
```bash
bin/test
```

### Run a single Ruby test
```bash
bin/test test/builder_test.rb
bin/test test/builder_test.rb -i test_method_name # or -i "/regexp/"; -n is deprecated in Minitest 6
bin/test test/builder_test.rb:12 # line number of the test method definition
```

### Run Go tests
```bash
go test ./test ./internal/...
```

### Run the JavaScript tests (`bun test`, via the Proscenium harness)
```bash
cd fixtures/dummy && bun test test/js/
```

### Run Go benchmarks
```bash
go test ./test -bench=. -run="^$" -count=10 -benchmem
```

### Build gems for all platforms
```bash
bundle exec rake build
```

### Run tests across all supported Rails versions
```bash
bundle exec appraisal install
bundle exec appraisal bin/test
```

### Interactive console
```bash
bin/console
```

### Ruby benchmarks
```bash
./bench.rb <name>
```

### Linting
```bash
bundle exec rubocop
golangci-lint run
```

## Testing

- Ruby tests use Minitest (with Maxitest) and are in `test/`
- Ruby tests use RSpec-style DSL: `describe`, `context` (aliased as `with`), `it`
- Test helper sets `ENV['PROSCENIUM_TESTS'] = '1'`
- Go tests use Ginkgo/Gomega and are in `test/`
- Go test suite file: `test/proscenium_suite_test.go`
- A white-box test that needs a package's unexported state lives beside it as a plain `testing`
  test (`internal/css/parser_internal_test.go`, for a parser path no CSS input can reach)
- Custom Go test matchers: `ContainCode`, `BeParsedTo(expected, path, cfg, warnings...)` (in `test/support/`); pass `BeParsedTo` the spec's `testConfig`, and every warning the parse must produce
- Go test helpers: `EntryPoint()`, `AssertCode()` — use markers `Bundle`, `Unbundle`, `Production` for options
- Go tests build a fresh per-spec `testConfig` in BeforeEach (with `InternalTesting: true`), not the old shared `types.Config` global
- JS tests use `bun:test` and live in `fixtures/dummy/test/js/`, loaded through the preload at `fixtures/dummy/test/proscenium.preload.js`
- `bun test` runs the app's real modules through a Rails daemon, so it needs the Go library compiled first, same as the Ruby tests
- A dummy Rails app for integration testing is at `fixtures/dummy/`
- `fixtures/adopted/` is a second Rails app, one that has adopted gem dependency contexts (#154): its own Gemfile, pnpm 11 lock and committed `.proscenium/packages/`. `test/adopted/` drives it as a subprocess, because the engine reads contexts at `Bundler.root`; it runs with `STAGE_A=1`. After changing its Gemfile, keep every gem at the version the repo's Gemfile.lock has, so CI installs it with `--local`
- Dummy app uses pnpm as its package manager
- Multi-Rails version testing uses Appraisals: `gemfiles/rails_7.2.gemfile`, `gemfiles/rails_8.gemfile` (Rails 8.0) and `gemfiles/rails_8.1.gemfile`

## CI

- GitHub Actions (`.github/workflows/main.yml`): runs on ubuntu-latest, macos-latest and windows-latest.
  The Windows jobs check out with `core.symlinks`, `core.longpaths` and `core.autocrlf false`; see
  the comment in go-test for why each one matters
- CI sets `GOWORK=off` and `RAILS_ENV=test`
- CI compiles Go with: `go build -mod=readonly -buildmode=c-shared -o lib/proscenium/ext/proscenium main.go`
  (`proscenium.dll` on Windows, which `rake compile:local` also produces there)
- Rubocop runs with `-P --fail-level C`

## Go Package Structure

- `internal/builder/` - Build orchestration (build, build_to_string, compile)
- `internal/plugin/` - esbuild plugins: css, svg, i18n, rjs, http, dirname, replacements, bundler, bundless
- `internal/resolver/` - Path resolution
- `internal/types/` - Shared types and config struct
- `internal/css/` - CSS parser, tokenizer, mixins
- `internal/replacements/` - Build-time replacements
- `internal/utils/`, `internal/debug/` - Utilities

## Cross-Platform Builds

The gem ships with precompiled Go binaries per platform. `PLATFORMS` in the Rakefile is the single
source of truth; the release workflow derives its build matrix from it via `rake platforms:json`,
so another target one of the existing builders already covers - a darwin arch, a glibc Linux
arch, or a Windows arch - is a one-line change there, plus a leg in `release.yml`'s `verify` or
`verify-native` matrix, which are written by hand. A platform needing a builder that does not
exist yet needs a build job as well.

- `x86_64-darwin`, `arm64-darwin` (macOS) - built natively, `CGO_ENABLED=1`
- `x86_64-linux-gnu`, `aarch64-linux-gnu` (Linux) - cross-compiled with
  [xgo](https://github.com/techknowlogick/xgo), pinned to a version
- `x64-mingw-ucrt` (Windows) - built natively on `windows-latest`, `CGO_ENABLED=1`. The library is
  `proscenium.dll`, not `proscenium`. `xgo` cannot build it: its linker fails with
  `x86_64-w64-mingw32-ld: export_file.def:1: syntax error`

The Linux gems name their libc deliberately. A bare `x86_64-linux` matches glibc and musl alike, so
Alpine used to install a glibc library it could not load. `-gnu` is never selected on musl, so a
musl host now matches no platform gem, gets the platform-less gem, and sees
`Proscenium::Builder::UnsupportedPlatform` naming its platform. That gem carries no compiled
library at all: the gemspec ships `lib/proscenium/ext/**` only when `PROSCENIUM_PACKAGE_EXT` is
set, which the platform build tasks set for the `gem build` subprocess alone.

**There are no musl gems, and this is not an oversight.** Go's `-buildmode=c-shared` libraries
carry initial-exec TLS relocations, which musl refuses to `dlopen` by design, and FFI loads this
library with `dlopen`. The build succeeds and is correctly musl-linked; it simply cannot be loaded.
That is [golang/go#54805](https://github.com/golang/go/issues/54805), and the linker flag that
fixes it is in neither Go 1.25 nor 1.27. Revisit when it ships - nothing else needs to change.

**Windows** runs `go test`, `bin/test` and `bun test` in CI. The path convention it needed is the
TWO PATH SPACES comment in `internal/utils/utils.go`, with `Utils.fs_path` as its Ruby side.

## Releasing

Releases run from `.github/workflows/release.yml`, not from a laptop. Push a `v*` tag.

The workflow builds every platform gem plus the platform-less one, then refuses to publish until
those exact archives have passed two different checks.

The built gems are served from a generated index and installed from it, so RubyGems performs the
same platform selection a user gets. `bin/verify-installed-gem` then checks the platform it
resolved, loads the library from the installed copy, and calls into Go - five times, each required
to exit cleanly, because the Windows exit crash was intermittent. It installs Proscenium with
`--ignore-dependencies` and then only ffi: the index holds nothing but Proscenium, and resolving
rails from it fails. `bin/verify-gem` runs it inside a container for `x86_64-linux-gnu`, and
`aarch64-linux-gnu` under QEMU; `verify-native` runs it directly on the hosts a container cannot
stand in for - `windows-latest` for `x64-mingw-ucrt`, `macos-latest` for `arm64-darwin`, and
`macos-15-intel` for `x86_64-darwin`. So every platform gem is installed and loaded before anything
publishes. No leg resolves to the platform-less gem, because on every leg a platform gem wins;
that is still a TODO.

To run all of it without publishing, dispatch the workflow from any branch with `dry_run`
(`gh workflow run release.yml --ref <branch> -f dry_run=true`). Publishing also needs the run to
be on a `v*` tag, so a dispatch from a branch cannot publish whatever `dry_run` says.

The platform-less gem is covered a different way: `build-plain` builds it in a job that never
compiles anything, then lists the archive and fails on any `lib/proscenium/ext/` entry. That is
what addresses 0.25.2, where `rake build` ran the platform compiles first and packed the plain gem
last in the same tree, so it shipped an x86-64 Linux ELF. Reading the gemspec's file list cannot
see a stray file left on disk between two rake tasks; only the archive can.

Publishing uses RubyGems trusted publishing (OIDC), so there is no API key anywhere. It needs the
`release` GitHub environment, which has a required reviewer, so a publish waits for approval.
`rake push` skips any gem already published at that version, so a run that dies partway is
finished by re-running it rather than by pushing the remainder by hand.

To check the credential path without publishing, dispatch the workflow with `verify_publisher`. It
performs the OIDC exchange, confirms RubyGems issued a scoped key, and stops. Worth doing before a
first release so that is not also the first test of trusted publishing.

`bundle exec rake build` builds what the machine can: the Linux gems anywhere Docker runs (they go
through xgo), and the natively built gems only for the machine's own OS, so a Mac skips Windows and
says so. The plain gem it produces inherits whatever the last compile left behind unless
`PROSCENIUM_PACKAGE_EXT` is unset for that build. Prefer the workflow, which is the only thing that
builds every platform.

## Gotchas

- **Compile before testing**: You must run `bundle exec rake compile:local` before running Ruby tests. The Go shared library must be built first.
- **go.work and the esbuild fork**: The project uses a Go workspace (`go.work`) pointing at `../esbuild-internal`, the importable copy of the esbuild fork. Do not edit it: every file in it is generated by its `update.sh` from the fork itself, `github.com/joelmoss/esbuild` (checked out as a sibling, `../esbuild`), with the layout flattened, so the fork's `pkg/api/api_impl.go` and `internal/js_parser/js_parser.go` are `api/api_impl.go` and `js_parser/js_parser.go` in `esbuild-internal`. Make changes in `../esbuild`, then regenerate and tag with `update.sh` (see `esbuild-internal`'s README). Set `GOWORK=off` in CI or when not developing against the local esbuild fork.
- **FFI boundary**: Ruby communicates with Go via C-exported functions in `main.go`. Changes to the Go function signatures require matching updates in `lib/proscenium/builder.rb`.
- **Middleware stack**: `lib/proscenium/middleware/` contains multiple specialized middleware (Esbuild, RubyGems, Vendor, Chunks, etc.), not just the main `middleware.rb`.
- **Go FFI functions** (`main.go`): `build_to_string(filePath, configJson)`, `resolve(filePath, configJson)`, `compile(configJson)`, `free_cstr(ptr)` and `reset_config()`. The first three accept JSON config and return C structs. `free_cstr(ptr)` frees a string Go allocated with `C.CString`, which the Go runtime cannot collect; Ruby calls it on every result string once read (`read_and_free` in `lib/proscenium/builder.rb`). `reset_config()` takes nothing and does nothing; it is kept as the one call into Go that needs no Rails app, for bin/verify-installed-gem and the packaging test, and as the bare FFI-call cost that benchmarks/bridge.rb times. Check `Result`, `ResolveResult`, `CompileResult` struct definitions when modifying.
- **go.work is gitignored**: The `go.work` and `go.work.sum` files are not checked in. Each developer needs their own pointing to their local esbuild fork.
- **Compiled binaries are gitignored**: `lib/proscenium/ext/` contents (`.so`, `.h` files) are not checked in.
- **Go runtime + Puma `preload_app!` fork hazard**: never call `Builder.build_to_string`/`resolve`/`compile` from a Rails boot-time initializer. Go's runtime cannot survive a `fork()` once it has been initialized (see [golang/go#15538](https://github.com/golang/go/issues/15538), unfixed) - a `preload_app!` + `workers` Puma setup forks after boot, so any pre-fork Go call would break every worker. The Go runtime only initializes lazily on the first actual builder call, and stock Proscenium's own boot sequence never triggers it - this only bites if custom app code calls a builder method during boot. See README's "Puma preload_app! and Cluster Mode" section.

## Environment quirks (agent shells)

- The shell is zsh: quote globs (`--include='*.go'`), because one that matches nothing aborts the
  whole command, and never `echo ===`, which zsh expands as a command name.
- Under the sandbox, Go needs `GOCACHE=$TMPDIR/gocache GOWORK=off`. The full `bin/test` suite,
  `git branch -m` / `git switch -c` (they write `.git/config`) and Bun unix sockets need the sandbox
  off. Sandboxed and unsandboxed shells see different `TMPDIR`s, so a file one writes there is
  invisible to the other.
- `fsmonitor_ipc__send_query` errors on git calls are noise (`core.fsmonitor=true` plus the
  sandbox blocking its socket); use `git -c core.fsmonitor=false`.
- Always pass `rg` a path, or it reads stdin and hangs.

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec

## Agent skills

### Issue tracker

Issues live in GitHub Issues for joelmoss/proscenium, via the `gh` CLI. PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. Both are created lazily, by
`/domain-modeling` when a term or decision is first settled, so either may be missing: proceed
without it. See `docs/agents/domain.md`.
