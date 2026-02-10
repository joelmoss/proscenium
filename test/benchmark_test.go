package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path"
	"path/filepath"
	"runtime"
	"testing"
)

func benchSetup() {
	_, filename, _, _ := runtime.Caller(1)
	root := path.Dir(filename)
	types.Config.RootPath = path.Join(root, "..", "fixtures", "dummy")
	types.Config.OutputDir = "public/assets"
	types.Config.Environment = types.TestEnv
	types.Config.InternalTesting = true
	types.Config.GemPath = path.Join(root, "..")
}

func BenchmarkCssBuild(bm *testing.B) {
	benchSetup()

	fixturesPath := filepath.Join(types.Config.RootPath, "..")
	types.Config.RubyGems = map[string]string{
		"gem1": filepath.Join(fixturesPath, "dummy", "vendor", "gem1"),
		"gem2": filepath.Join(fixturesPath, "external", "gem2"),
	}

	for bm.Loop() {
		success, result, _ := b.BuildToString("lib/css_all/index.css")

		if !success {
			panic("Build failed: " + result)
		}
	}
}

func BenchmarkCssModuleFromJs(bm *testing.B) {
	benchSetup()

	for bm.Loop() {
		success, result, _ := b.BuildToString("lib/css_modules/import_css_module.js")

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
