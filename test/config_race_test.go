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

// Reproduces the data race below main.go's callMutex: internal/builder and internal/replacements
// used to rely on unsynchronised package-level globals (types.Config, the builder package's env
// var cache, and internal/replacements.npmReplacements), on the assumption that only one
// goroutine is ever inside this library at a time.
//
// That assumption held while Ruby's GVL was held for the full duration of build_to_string/
// resolve/compile. Now that the GVL is released (blocking: true), main.go's callMutex is the
// only thing enforcing it in production - this test bypasses that mutex by calling straight
// into the internal packages, to prove the race exists below it.
//
// Status as of the global config refactor's Phase 1 (types.NewConfig; cfg threaded explicitly
// through builder/resolver/plugins; the env var cache deleted, always recomputed instead):
//   - npmReplacements: fixed earlier via sync.Once (commit 726b6a8a) - no longer reproduces.
//   - envVarMap: gone entirely as of Phase 1 - each call now builds its own local map, so this
//     test's original "concurrent map writes" crash no longer reproduces either.
//   - types.Config itself: this test only reads it concurrently (never calls UnmarshalConfig
//     mid-test), so no write-race is exercised here regardless of Phase 1. main.go's
//     unmarshalConfigIfChanged writing to the same global while other goroutines read it
//     remains a real, reachable race below the mutex - this test just doesn't trigger it, since
//     that needs concurrent config CHANGES, not concurrent builds against a static one. Phase 3
//     is scoped to rewrite this test to exercise that directly (distinct config per goroutine).
//
// This test currently passes clean under `go test -race` - that reflects Phase 1's real
// progress, not a false negative on a risk that no longer exists.
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
