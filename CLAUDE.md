# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Proscenium is a Rails engine that provides real-time frontend asset bundling and minification using esbuild. It processes JavaScript, TypeScript, JSX, TSX, and CSS files on-demand with zero configuration and no build step.

## Prerequisites

- Ruby >= 3.3.0 (project uses 3.3.8)
- Go 1.25+
- Rails 7.1 to 8.x

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
- `main.go` - C-exported functions (`build_to_string`, `resolve`, `compile`) called from Ruby
- `internal/builder/` - esbuild configuration and build orchestration
- `internal/plugin/` - Custom esbuild plugins (CSS modules, SVG, i18n, RJS, etc.)

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
bin/test test/builder_test.rb -n test_method_name
bin/test test/builder_test.rb:12 # line number of the test method definition
```

### Run Go tests
```bash
go test ./test
```

### Run Go benchmarks
```bash
go test ./internal/builder -bench=. -run="^$" -count=10 -benchmem
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
- Test helper sets `ENV['PROSCENIUM_TESTS'] = '1'` and uses DatabaseCleaner with transactions
- Go tests use Ginkgo/Gomega and are in `test/`
- Go test suite file: `test/proscenium_suite_test.go`
- Custom Go test matchers: `ContainCode`, `EqualCode`, `BeParsedTo` (in `test/support/`)
- Go test helpers: `EntryPoint()`, `AssertCode()` — use type aliases `Debug`, `Bundle`, `Unbundle`, `Production` for options
- Go tests reset config and set `types.Config.InternalTesting = true` in BeforeEach
- A dummy Rails app for integration testing is at `fixtures/dummy/`
- Dummy app uses pnpm as its package manager
- Multi-Rails version testing uses Appraisals (gemfiles for Rails 7.1, 7.2, 8.0, 8.1)

## CI

- GitHub Actions (`.github/workflows/main.yml`): runs on ubuntu-latest + macos-latest
- CI sets `GOWORK=off` and `RAILS_ENV=test`
- CI compiles Go with: `go build -mod=readonly -buildmode=c-shared -o lib/proscenium/ext/proscenium main.go`
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

The gem ships with precompiled Go binaries for multiple platforms. The Rakefile defines compile tasks for:
- `x86_64-darwin`, `arm64-darwin` (macOS)
- `x86_64-linux`, `aarch64-linux` (Linux)

Linux builds use [xgo](https://github.com/techknowlogick/xgo) for cross-compilation.

## Gotchas

- **Compile before testing**: You must run `bundle exec rake compile:local` before running Ruby tests. The Go shared library must be built first.
- **go.work**: The project uses a Go workspace (`go.work`) pointing to a local fork of esbuild (`esbuild-internal`). Set `GOWORK=off` in CI or when not developing against the local esbuild fork.
- **FFI boundary**: Ruby communicates with Go via C-exported functions in `main.go`. Changes to the Go function signatures require matching updates in `lib/proscenium/builder.rb`.
- **Middleware stack**: `lib/proscenium/middleware/` contains multiple specialized middleware (Esbuild, RubyGems, Vendor, Chunks, etc.), not just the main `middleware.rb`.
- **Go FFI functions** (`main.go`): `build_to_string(filePath, configJson)`, `resolve(filePath, configJson)`, `compile(configJson)`, `reset_config()`. All accept JSON config and return C structs. Check `Result`, `ResolveResult`, `CompileResult` struct definitions when modifying.
- **go.work is gitignored**: The `go.work` and `go.work.sum` files are not checked in. Each developer needs their own pointing to their local esbuild fork.
- **Compiled binaries are gitignored**: `lib/proscenium/ext/` contents (`.so`, `.h` files) are not checked in.
