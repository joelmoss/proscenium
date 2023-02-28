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
var outDir string = path.Join(root, "public/assets")

func build(path string) api.BuildResult {
	return golib.Build(golib.BuildOptions{
		Path: path,
		Root: root,
		Env:  2,
	})
}

func TestBuild(t *testing.T) {
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

		assert.Equal(t, result.OutputFiles[0].Path, path.Join(outDir, "lib/component.js"))
	})

	t.Run("NODE_ENV is defined", func(t *testing.T) {
		result := build("lib/define_node_env.js")

		assert.Contains(t, string(result.OutputFiles[0].Contents), "console.log(\"test\")")
	})
}
