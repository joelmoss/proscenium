//go:build race

// This file only compiles when `go test -race` is used - see the comment on
// TestConcurrentBuildToStringRace below for why. Go automatically defines the `race` build tag
// when -race is passed.

package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"strings"
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
// Phase 3: rewritten to actually prove parallel CORRECTNESS, not just absence-of-crash. Each
// goroutine now gets its own genuinely different *types.ConfigT (built independently, matching
// main.go's real parseConfig-per-call shape - no shared &types.Config across goroutines
// anymore) and asserts its OWN build output reflects ITS OWN config, not another goroutine's -
// distinguished by Environment (development/test/production), which build.go bakes into the
// output via the proscenium.env.RAILS_ENV define. If two goroutines' configs were ever crossed
// (e.g. a future regression reintroduces shared state), this would catch it as a wrong-value
// assertion failure, not just a crash - the exact class of bug -race alone can't see (wrong
// data served, not a data race).
func TestConcurrentBuildToStringRace(t *testing.T) {
	environments := []types.Environment{types.DevEnv, types.TestEnv, types.ProdEnv}

	var wg sync.WaitGroup
	for i := range 8 {
		env := environments[i%len(environments)]

		wg.Go(func() {
			cfg := newTestConfig()
			cfg.Environment = env
			expected := env.String()

			for range 50 {
				success, result, _ := b.BuildToString("lib/env_vars.js", cfg)
				if !success {
					t.Errorf("build failed: %s", result)
					return
				}
				if !strings.Contains(result, expected) {
					t.Errorf("expected build output to contain %q (this goroutine's own Environment), got: %s", expected, result)
					return
				}
			}
		})
	}
	wg.Wait()
}
