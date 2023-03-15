package golib_test

import (
	"joelmoss/proscenium/golib"
	"os"
	"path"
	"testing"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/stretchr/testify/assert"
)

var cwd, _ = os.Getwd()
var root string = path.Join(cwd, "../", "test", "internal")

func TestBuild(t *testing.T) {
	build := func(path string) api.BuildResult {
		return golib.Build(golib.BuildOptions{
			Path: path,
			Root: root,
			Env:  2,
		})
	}

	t.Run("simple js", func(t *testing.T) {
		result := build("lib/foo.js")

		assert.Contains(t, string(result.OutputFiles[0].Contents), "console.log(\"/lib/foo.js\")")
	})

	t.Run("unknown entrypoint", func(t *testing.T) {
		result := build("unknown.js")

		assert.Equal(t, result.Errors[0].Text, "Could not resolve \"unknown.js\"")
	})

	t.Run("jsx", func(t *testing.T) {
		result := build("lib/component.jsx")

		assert.Equal(t, result.OutputFiles[0].Path, path.Join(path.Join(root, "public/assets"), "lib/component.js"))
	})

	t.Run("NODE_ENV is defined", func(t *testing.T) {
		result := build("lib/define_node_env.js")

		assert.Contains(t, string(result.OutputFiles[0].Contents), "console.log(\"test\")")
	})
}

func TestImportMap(t *testing.T) {
	build := func(path string, importMap []byte) api.BuildResult {
		return golib.Build(golib.BuildOptions{
			Path:      path,
			Root:      root,
			Env:       2,
			Debug:     true,
			ImportMap: importMap,
		})
	}

	t.Run("js map", func(t *testing.T) {
		result := golib.Build(golib.BuildOptions{
			Path:          "lib/import_map/as_js.js",
			Root:          root,
			Env:           2,
			Debug:         true,
			ImportMapPath: "config/import_maps/as.js",
		})

		assert.Contains(t, string(result.OutputFiles[0].Contents), "import pkg from \"/lib/foo2.js\";")
	})

	t.Run("bare specifier", func(t *testing.T) {
		result := build("lib/import_map/bare_specifier.js", []byte(`{
			"imports": { "foo": "/lib/foo.js" }
		}`))

		assert.Contains(t, string(result.OutputFiles[0].Contents), "import foo from \"/lib/foo.js\";")
	})

	t.Run("path prefix", func(t *testing.T) {
		result := build("lib/import_map/path_prefix.js", []byte(`{
			"imports": { "one/": "./src/one/" }
		}`))

		assert.Contains(t, string(result.OutputFiles[0].Contents), "import four from \"./src/one/two/three/four.js\";")
	})

	t.Run("path prefix multiple matches", func(t *testing.T) {
		result := build("lib/import_map/path_prefix.js", []byte(`{
			"imports": {
				"one/": "./one/",
				"one/two/three/": "./three/",
				"one/two/": "./two/"
			}
		}`))

		assert.Contains(t, string(result.OutputFiles[0].Contents), "import four from \"./three/four.js\";")
	})
}
