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
- Go tests use Ginkgo/Gomega and are in `test/`
- A dummy Rails app for integration testing is at `fixtures/dummy/`
- Multi-Rails version testing uses Appraisals (gemfiles for Rails 7.1, 7.2, 8.0, 8.1)

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
