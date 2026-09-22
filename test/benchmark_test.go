package proscenium_test

import (
	"fmt"
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"testing"
)

func BenchmarkCssBuild(bm *testing.B) {
	cfg := newTestConfig()

	fixturesPath := utils.JoinFsPath(cfg.RootPath, "..")
	cfg.RubyGems = map[string]string{
		"gem1": utils.JoinFsPath(fixturesPath, "dummy", "vendor", "gem1"),
		"gem2": utils.JoinFsPath(fixturesPath, "external", "gem2"),
	}

	for bm.Loop() {
		success, result, _ := b.BuildToString("lib/css_all/index.css", cfg)

		if !success {
			panic("Build failed: " + result)
		}
	}
}

func BenchmarkCssModuleFromJs(bm *testing.B) {
	cfg := newTestConfig()

	for bm.Loop() {
		success, result, _ := b.BuildToString("lib/css_modules/import_css_module.js", cfg)

		if !success {
			panic("Build failed: " + result)
		}
	}
}

func BenchmarkUtils(bm *testing.B) {
	bm.Run("IsUrl", func(bm *testing.B) {
		for bm.Loop() {
			utils.IsUrl("https://example.com/foo.js")
			utils.IsUrl("http://example.com/bar.js")
			utils.IsUrl("./relative/path.js")
			utils.IsUrl("/absolute/path.js")
		}
	})

	bm.Run("PathIsRelative", func(bm *testing.B) {
		for bm.Loop() {
			utils.PathIsRelative("./relative/path.js")
			utils.PathIsRelative("../parent/path.js")
			utils.PathIsRelative("/absolute/path.js")
			utils.PathIsRelative("bare-module")
		}
	})

	// Runs for every module a build loads, against every gem in Gemfile.lock. The roots are as long
	// as real install paths, so a per-gem allocation shows up here as well as in the spec that counts
	// them.
	bm.Run("GemFromFsPath", func(bm *testing.B) {
		const installDir = "/Users/someone/.local/share/mise/installs/ruby/3.4.9/lib/ruby/gems/3.4.0/gems"

		gems := make(map[string]string, 300)
		for i := range 300 {
			gems[fmt.Sprintf("gem-%03d", i)] = fmt.Sprintf("%s/gem-%03d-1.2.3", installDir, i)
		}
		cfg := &types.ConfigT{RubyGems: gems}

		bm.ReportAllocs()

		for bm.Loop() {
			utils.GemFromFsPath("/Users/someone/dev/app/app/javascript/x.js", cfg)
			utils.GemFromFsPath(installDir+"/gem-150-1.2.3/lib/x.js", cfg)
		}
	})

	bm.Run("IsBareModule", func(bm *testing.B) {
		for bm.Loop() {
			utils.IsBareModule("pkg")
			utils.IsBareModule("@scope/pkg")
			utils.IsBareModule("./relative")
			utils.IsBareModule("/absolute")
		}
	})
}
