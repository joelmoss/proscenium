package golib_test

import (
	"joelmoss/proscenium/golib"
	"os"
	"path"
	"testing"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/gkampitakis/go-snaps/snaps"
	"github.com/k0kubun/pp/v3"
	"github.com/stretchr/testify/assert"
)

func TestMain(t *testing.M) {
	v := t.Run()
	snaps.Clean(t)
	os.Exit(v)
}

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

	t.Run("fails on unknown entrypoint", func(t *testing.T) {
		result := build("unknown.js")

		assert.Equal(t, result.Errors[0].Text, "Could not resolve \"unknown.js\"")
	})

	t.Run("build js", func(t *testing.T) {
		result := build("lib/foo.js")

		assert.Contains(t, string(result.OutputFiles[0].Contents), "console.log(\"/lib/foo.js\")")
	})

	t.Run("build jsx", func(t *testing.T) {
		result := build("lib/component.jsx")

		assert.Equal(t, path.Join(path.Join(root, "public/assets"), "lib/component.js"),
			result.OutputFiles[0].Path)
	})

	t.Run("build css", func(t *testing.T) {
		result := build("lib/foo.css")

		snaps.MatchSnapshot(t, string(result.OutputFiles[0].Contents))
	})

	t.Run("import bare module", func(t *testing.T) {
		result := build("lib/import_npm_module.js")

		assert.Contains(t, string(result.OutputFiles[0].Contents),
			`import { isIP } from "/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js"`)
	})

	t.Run("import relative path", func(t *testing.T) {
		result := build("lib/import_relative_module.js")

		assert.Contains(t, string(result.OutputFiles[0].Contents),
			`import foo4 from "/lib/foo4.js"`)
	})

	t.Run("import absolute path", func(t *testing.T) {
		result := build("lib/import_absolute_module.js")

		assert.Contains(t, string(result.OutputFiles[0].Contents),
			`import foo4 from "/lib/foo4.js"`)
	})

	t.Run("import css module from js", func(t *testing.T) {
		result := build("lib/import_css_module.js")

		pp.Println(result)
		pp.Println(string(result.OutputFiles[0].Contents))

		assert.Contains(t, string(result.OutputFiles[0].Contents),
			`import foo4 from "/lib/foo4.js"`)
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

	t.Run("scopes", func(t *testing.T) {
		result := build("lib/import_map/scopes.js", []byte(`{
			"imports": {
				"foo": "/lib/foo.js"
			},
			"scopes": {
				"/lib/import_map/": {
					"foo": "/lib/foo4.js"
				}
			}
		}`))

		assert.Contains(t, string(result.OutputFiles[0].Contents), "import foo from \"/lib/foo4.js\";")
	})

	t.Run("path prefix", func(t *testing.T) {
		// import four from 'one/two/three/four.js'
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
