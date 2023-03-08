package golib_plugin_test

import (
	"joelmoss/proscenium/golib"
	"os"
	"path"
	"testing"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/k0kubun/pp/v3"
	"github.com/stretchr/testify/assert"
)

var cwd, _ = os.Getwd()
var root string = path.Join(cwd, "../../", "test", "internal")

func build(path string, importMap string) api.BuildResult {
	return golib.Build(golib.BuildOptions{
		Path:      path,
		Root:      root,
		ImportMap: importMap,
		Env:       2,
	})
}

func TestImportMap(t *testing.T) {
	t.Run("simple js", func(t *testing.T) {
		result := build("lib/import_map/simple.js", "config/import_maps/simple.json")

		pp.Print(result)
		assert.Contains(t, string(result.OutputFiles[0].Contents), "import foo from \"/lib/foo.js\";")
	})
}
