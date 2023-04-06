package plugin_test

import (
	"joelmoss/proscenium/golib/plugin"
	"os"
	"path"
	"testing"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/k0kubun/pp/v3"
)

func TestCssPlugin(t *testing.T) {
	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	t.Run("build CSS", func(t *testing.T) {
		result := api.Build(api.BuildOptions{
			EntryPoints:   []string{"lib/foo.css"},
			AbsWorkingDir: root,
			Bundle:        true,
			Write:         false,
			Supported: map[string]bool{
				"nesting": false,
			},
			Plugins: []api.Plugin{plugin.Css()},
		})

		pp.Println(result)
		pp.Printf(string(result.OutputFiles[0].Contents))

		// snaps.MatchSnapshot(t, string(result.OutputFiles[0].Contents))
	})
}
