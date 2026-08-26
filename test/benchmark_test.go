package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/utils"
	"path/filepath"
	"testing"
)

func BenchmarkCssBuild(bm *testing.B) {
	cfg := newTestConfig()

	fixturesPath := filepath.Join(cfg.RootPath, "..")
	cfg.RubyGems = map[string]string{
		"gem1": filepath.Join(fixturesPath, "dummy", "vendor", "gem1"),
		"gem2": filepath.Join(fixturesPath, "external", "gem2"),
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

	bm.Run("IsBareModule", func(bm *testing.B) {
		for bm.Loop() {
			utils.IsBareModule("pkg")
			utils.IsBareModule("@scope/pkg")
			utils.IsBareModule("./relative")
			utils.IsBareModule("/absolute")
		}
	})
}
