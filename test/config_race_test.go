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

// Reproduces the data race below main.go's callMutex: internal/builder, internal/types and
// internal/replacements all rely on unsynchronised package-level globals (types.Config, the
// builder package's env var cache, and internal/replacements.npmReplacements), on the
// assumption that only one goroutine is ever inside this library at a time.
//
// That assumption held while Ruby's GVL was held for the full duration of build_to_string/
// resolve/compile. Now that the GVL is released (blocking: true), main.go's callMutex is the
// only thing enforcing it in production - this test bypasses that mutex by calling straight
// into the internal packages, to prove the race exists below it.
//
// Confirmed: this reliably crashes the whole process with "fatal error: concurrent map writes"
// in internal/replacements.Build (lazy-populates npmReplacements with an unsynchronised
// length check instead of sync.Once) - reproducible even without -race, since Go's map
// implementation detects concurrent writes at runtime regardless. -race additionally catches
// the same shape of race in types.Config and the builder package's env var cache.
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
				b.BuildToString("lib/foo.js")
			}
		})
	}
	wg.Wait()
}
