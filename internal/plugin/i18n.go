package plugin

import (
	"encoding/json"
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"

	esbuild "github.com/evanw/esbuild/pkg/api"
	"github.com/peterbourgon/mergemap"
	yaml "gopkg.in/yaml.v3"
)

var localeFiles *[]string
var jsonContents *[]byte

var I18n = esbuild.Plugin{
	Name: "i18n",
	Setup: func(build esbuild.PluginBuild) {
		cwd := build.InitialOptions.AbsWorkingDir
		root := filepath.Join(cwd, "config", "locales")

		build.OnResolve(esbuild.OnResolveOptions{Filter: `^proscenium/i18n$`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				return esbuild.OnResolveResult{
					Path:      args.Path,
					Namespace: "i18n",
				}, nil
			})

		build.OnLoad(esbuild.OnLoadOptions{Filter: `\.*`, Namespace: "i18n"},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				// Fetch map of all locale files in config/locales. This is cached in production, which
				// means that any other environment will pick up new or deleted files without a restart.
				if types.Config.Environment != types.ProdEnv || localeFiles == nil {
					matches, err := filepath.Glob(root + "/*.yml")
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					localeFiles = &matches
				}

				// Fetch contents of the locale files. This is cached in production, which means that any
				// other environment will pick up changes in the locale file contents without a restart.
				// TODO: Use goroutines?
				if types.Config.Environment != types.ProdEnv || jsonContents == nil {
					var contents = map[string]any{}

					for _, path := range *localeFiles {
						// Get file contents.
						data, err := os.ReadFile(path)
						if err != nil {
							panic(err)
						}

						// Parse file contents as YAML.
						var yamlData map[string]any
						err = yaml.Unmarshal([]byte(data), &yamlData)
						if err != nil {
							panic(err)
						}

						// Merge YAML of current file with previous.
						contents = mergemap.Merge(contents, yamlData)
					}

					// Convert merged YAML to JSON.
					c, err := json.Marshal(contents)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					jsonContents = &c
				}

				contentsAsString := string(*jsonContents)

				return esbuild.OnLoadResult{
					Contents: &contentsAsString,
					Loader:   esbuild.LoaderJSON,
				}, nil
			})
	},
}
