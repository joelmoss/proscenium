package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

// Every on-demand build writes its code-split chunks into the one shared `_asset_chunks`
// directory, and the chunks middleware serves them straight from there. A chunk is named by its
// content hash, so a second build of the same entry point writes byte-identical content to the
// same path - but it rewrites it all the same, by truncating the file and then writing it, and
// anything reading the chunk in between gets an empty or partial file. A browser importing from
// it then fails with `The requested module './chunk-$HASH$.js' does not provide an export named
// '__commonJS'`, which is what a page loading several entry points at once hit in CI.
//
// So a chunk that is already on disk has to read back whole, however many builds are running.
func TestChunkReadsWhileRebuilding(t *testing.T) {
	cfg, chunk, want := buildChunkApp(t)

	reads, seen, bad := readWhileBuilding(t, cfg, chunk, want)

	if seen != reads || bad > 0 {
		t.Errorf("%d of %d reads of %s were missing or differed from the chunk that was built",
			reads-seen+bad, reads, filepath.Base(chunk))
	}
}

// The same, from cold: several builds find the chunk missing and race to create it. A read can
// find nothing there yet, but whatever it does find must be the whole chunk.
func TestChunkReadsWhileCreating(t *testing.T) {
	cfg, chunk, want := buildChunkApp(t)
	if err := os.Remove(chunk); err != nil {
		t.Fatal(err)
	}

	reads, seen, bad := readWhileBuilding(t, cfg, chunk, want)

	if seen == 0 {
		t.Fatalf("none of %d reads found %s, so nothing was checked", reads, filepath.Base(chunk))
	}
	if bad > 0 {
		t.Errorf("%d of %d reads of %s differed from the chunk that was built", bad, seen, filepath.Base(chunk))
	}
}

// A build whose output cannot be written fails, rather than handing back code that imports chunks
// that are not on disk, and leaves no temp file behind.
func TestBuildFailsWhenOutputCannotBeWritten(t *testing.T) {
	cfg, chunk, _ := buildChunkApp(t)

	// A directory where the chunk should be: the temp file gets written, and the rename onto it
	// fails.
	if err := os.Remove(chunk); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(chunk, "blocker"), 0755); err != nil {
		t.Fatal(err)
	}

	success, result, _ := b.BuildToString("entry.js", cfg)

	if success {
		t.Fatalf("expected the build to fail, got: %s", result)
	}
	if !strings.Contains(result, "Failed to write to output file") {
		t.Errorf("expected a write failure, got: %s", result)
	}
	if leftovers, _ := filepath.Glob(filepath.Join(filepath.Dir(chunk), ".esbuild-*.tmp")); len(leftovers) > 0 {
		t.Errorf("expected no temp files left behind, found %v", leftovers)
	}
}

// Builds an app whose entry point and its lazy import share one chunk, and returns the config,
// that chunk's path, and what it holds.
func buildChunkApp(t *testing.T) (*types.ConfigT, string, []byte) {
	t.Helper()

	// esbuild reports output paths with symlinks resolved (macOS's /var is /private/var), and
	// BuildToString finds the entry point's output by comparing against the root it was given.
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		// CommonJS, so the chunk shared by the entry point and its lazy import carries esbuild's
		// `__commonJS` runtime helper.
		"shared.cjs": "module.exports = { shared: 'shared-marker' };\n",
		"lazy.js":    "import { shared } from './shared.cjs';\nexport default shared;\n",
		"entry.js":   "import { shared } from './shared.cjs';\nconsole.log(shared);\nimport('./lazy.js');\n",
	}
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(root, name), []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}

	cfg := &types.ConfigT{
		RootPath:        root,
		OutputDir:       "public/assets",
		Environment:     types.TestEnv,
		InternalTesting: true,
		CodeSplitting:   true,
		Bundle:          true,
	}

	if success, result, _ := b.BuildToString("entry.js", cfg); !success {
		t.Fatalf("build failed: %s", result)
	}

	chunks, _ := filepath.Glob(filepath.Join(root, "public/assets/_asset_chunks/chunk-*.js"))
	if len(chunks) != 1 {
		t.Fatalf("expected one shared chunk, got %v", chunks)
	}

	want, _ := os.ReadFile(chunks[0])
	if !strings.Contains(string(want), "__commonJS") {
		t.Fatalf("expected the shared chunk to carry the __commonJS helper, got: %s", want)
	}

	return cfg, chunks[0], want
}

// Rebuilds the entry point from several goroutines while reading the chunk over and over, and
// counts the reads, the reads that found the chunk, and those that found it different from `want`.
func readWhileBuilding(t *testing.T, cfg *types.ConfigT, chunk string, want []byte) (reads, seen, bad int) {
	t.Helper()

	var done atomic.Bool
	reader := sync.WaitGroup{}
	reader.Go(func() {
		for !done.Load() {
			contents, err := os.ReadFile(chunk)
			reads++
			if err != nil {
				continue
			}
			seen++
			if string(contents) != string(want) {
				bad++
			}
		}
	})

	var builders sync.WaitGroup
	for range 4 {
		builders.Go(func() {
			for range 50 {
				if success, result, _ := b.BuildToString("entry.js", cfg); !success {
					t.Errorf("build failed: %s", result)
					return
				}
			}
		})
	}

	builders.Wait()
	done.Store(true)
	reader.Wait()

	return reads, seen, bad
}
