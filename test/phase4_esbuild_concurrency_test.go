//go:build race

// This file only compiles when `go test -race` is used. Go automatically defines the `race`
// build tag when -race is passed.

package proscenium_test

import (
	"fmt"
	b "joelmoss/proscenium/internal/builder"
	r "joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// Phase 4 of the global config refactor plan: audit esbuild-internal's own concurrency safety,
// not just Proscenium's. Removing main.go's callMutex means esbuild-internal's Build()/Resolve()
// get invoked truly concurrently for the first time in this codebase's history -
// cache.MakeCacheSet() is confirmed fresh per call (read directly in esbuild-internal's
// api_impl.go), but that's one function checked once, not a full audit of a fork this project
// also maintains.
//
// Deliberately uses genuinely different RootPath values pointing at DISTINCT directory trees
// (not just different entry points against the same tree, which is what
// TestConcurrentBuildToStringRace in config_race_test.go already covers for Proscenium's own
// state). A shared-root workload could pass clean while still hiding a real bug that only
// surfaces cross-root - e.g. anything esbuild-internal keys by working directory. No second
// full fixture app exists in this repo, so this builds N independent temp directories instead,
// each with its own trivial, self-contained entry file - not dependent on fixtures/dummy's
// layout at all.
func TestPhase4EsbuildInternalConcurrency(t *testing.T) {
	const numRoots = 6

	roots := make([]string, numRoots)
	for i := range numRoots {
		dir := t.TempDir()
		entry := fmt.Sprintf("console.log(%q);\n", fmt.Sprintf("root-%d-marker", i))
		if err := os.WriteFile(filepath.Join(dir, "entry.js"), []byte(entry), 0644); err != nil {
			t.Fatal(err)
		}
		roots[i] = dir
	}

	var wg sync.WaitGroup
	for i := range numRoots {
		root := roots[i]
		marker := fmt.Sprintf("root-%d-marker", i)

		wg.Go(func() {
			cfg := &types.ConfigT{
				RootPath:        root,
				OutputDir:       "public/assets",
				Environment:     types.TestEnv,
				InternalTesting: true,
				CodeSplitting:   true,
				Bundle:          true,
			}

			for range 30 {
				success, result, _ := b.BuildToString("entry.js", cfg)
				if !success {
					t.Errorf("build failed for %s: %s", root, result)
					return
				}
				if !strings.Contains(result, marker) {
					t.Errorf("build for %s produced output missing its own marker %q - got: %s", root, marker, result)
					return
				}

				urlPath, absPath, err := r.Resolve("/entry.js", "", cfg)
				if err != nil {
					t.Errorf("resolve failed for %s: %s", root, err)
					return
				}
				if urlPath != "/entry.js" {
					t.Errorf("resolve for %s returned wrong urlPath: got %q", root, urlPath)
					return
				}
				if !strings.HasPrefix(absPath, root) {
					t.Errorf("resolve for %s returned absPath from a DIFFERENT root: got %q, want prefix %q - config crossed goroutines", root, absPath, root)
					return
				}
			}
		})
	}
	wg.Wait()
}
