package plugin_test

import (
	"joelmoss/proscenium/golib/plugin"
	"os"
	"path"
	"testing"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/gkampitakis/go-snaps/snaps"
)

func TestUrlPlugin(t *testing.T) {
	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	t.Run("import URL", func(t *testing.T) {
		result := api.Build(api.BuildOptions{
			EntryPoints:   []string{"lib/import_remote_module.js"},
			AbsWorkingDir: root,
			Format:        api.FormatESModule,
			Bundle:        true,
			Write:         false,
			Plugins:       []api.Plugin{plugin.Url},
		})

		snaps.MatchSnapshot(t, string(result.OutputFiles[0].Contents))
	})
}
