//go:build race

// This file only compiles when `go test -race` is used - see the comment on
// TestConcurrentBuildToStringRace below for why. Go automatically defines the `race` build tag
// when -race is passed.

package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"path"
	"runtime"
	"sync"
	"testing"
)

// Originally reproduced the data race below main.go's callMutex: internal/builder and
// internal/replacements used to rely on unsynchronised package-level globals (types.Config, the
// builder package's env var cache, and internal/replacements.npmReplacements), on the assumption
// that only one goroutine is ever inside this library at a time - an assumption that held only
// while Ruby's GVL was held for the full duration of build_to_string/resolve/compile.
//
// Status as of the global config refactor:
//   - npmReplacements: fixed via sync.Once (commit 726b6a8a) - no longer reproduces.
//   - envVarMap: deleted entirely in Phase 1 - each call builds its own local map now, so this
//     test's original "concurrent map writes" crash doesn't reproduce either.
//   - main.go's callMutex and unmarshalConfigIfChanged (the single shared *ConfigT they
//     protected) are both GONE as of Phase 2 - every build_to_string/resolve/compile call now
//     parses its own independent *ConfigT (types.NewConfig, no cache, no shared pointer). The
//     real FFI path has no shared config state left to race on at all.
//
// This test itself still calls internal/builder.BuildToString directly with a shared
// &types.Config across all 8 goroutines, bypassing main.go entirely - so it no longer reflects
// the real call path (which never shares a *ConfigT across calls post-Phase 2) and passes clean
// under `go test -race` for that reason, not because it's exercising and clearing a real risk.
// Phase 3 is scoped to rewrite this to go through the real parseConfig-per-call path with a
// genuinely different config per goroutine, which is now the only way this test would mean
// anything again.
func TestConcurrentBuildToStringRace(t *testing.T) {
	_, filename, _, _ := runtime.Caller(0)
	types.Config.RootPath = path.Join(path.Dir(filename), "..", "fixtures", "dummy")
	types.Config.OutputDir = "public/assets"
	types.Config.Environment = types.TestEnv
	types.Config.InternalTesting = true

	var wg sync.WaitGroup
	for range 8 {
		wg.Go(func() {
			for range 50 {
				b.BuildToString("lib/foo.js", &types.Config)
			}
		})
	}
	wg.Wait()
}
