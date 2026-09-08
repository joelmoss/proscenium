//go:build race

// Only compiles under `go test -race`, which defines the `race` build tag.

package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// The i18n locale cache is process-wide state reached from esbuild's plugin goroutines, and it
// used to have none of the synchronisation svg.go's equivalent cache has - three package-level
// variables with three independent write points, read from five places. `main.go` asserted that
// concurrent calls touch nothing shared, which was true of the config and false of this.
//
// Distinct roots on purpose: the cache is keyed by locales directory, so crossed payloads and an
// unsynchronised map are both only reachable with more than one root in flight.
func TestI18nConcurrentBuildRace(t *testing.T) {
	const numRoots = 4

	roots := make([]string, numRoots)
	for i := range numRoots {
		dir := t.TempDir()
		locales := filepath.Join(dir, "config", "locales")
		if err := os.MkdirAll(locales, 0o755); err != nil {
			t.Fatal(err)
		}

		name := rootName(i)
		if err := os.WriteFile(filepath.Join(locales, "en.yml"),
			[]byte("en:\n  who: "+name+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "entry.js"),
			[]byte("import locales from \"proscenium/i18n\";\nconsole.log(locales);\n"), 0o644); err != nil {
			t.Fatal(err)
		}

		roots[i] = dir
	}

	var wg sync.WaitGroup
	for i := range numRoots {
		root := roots[i]
		want := `who: "` + rootName(i) + `"`

		wg.Go(func() {
			cfg := &types.ConfigT{
				RootPath:        root,
				OutputDir:       "public/assets",
				Environment:     types.TestEnv,
				InternalTesting: true,
				CodeSplitting:   true,
				Bundle:          true,
			}

			for range 20 {
				success, result, _ := b.BuildToString("entry.js", cfg)
				if !success {
					t.Errorf("build failed for %s: %s", root, result)
					return
				}
				if !strings.Contains(result, want) {
					t.Errorf("build for %s is missing %s - got: %s", root, want, result)
					return
				}
			}
		})
	}

	wg.Wait()
}

func rootName(i int) string {
	return string(rune('a'+i)) + "pp"
}
