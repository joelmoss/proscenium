package plugin

import (
	"encoding/json"
	"os"
	"path/filepath"

	esbuild "github.com/evanw/esbuild/pkg/api"
	"github.com/peterbourgon/mergemap"
	yaml "gopkg.in/yaml.v3"
)

var I18n = esbuild.Plugin{
	Name: "i18n",
	Setup: func(build esbuild.PluginBuild) {
		cwd := build.InitialOptions.AbsWorkingDir
		root := filepath.Join(cwd, "config", "locales")

		build.OnResolve(esbuild.OnResolveOptions{Filter: `^@proscenium/i18n$`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				return esbuild.OnResolveResult{
					Path:      args.Path,
					Namespace: "i18n",
				}, nil
			})

		// TODO: Cache this!
		build.OnLoad(esbuild.OnLoadOptions{Filter: `\.*`, Namespace: "i18n"},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				matches, err := filepath.Glob(root + "/*.yml")
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				var contents map[string]interface{}
				contents = map[string]interface{}{}

				for _, path := range matches {
					data, err := os.ReadFile(path)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					var yamlData map[string]interface{}
					err = yaml.Unmarshal([]byte(data), &yamlData)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					contents = mergemap.Merge(contents, yamlData)
				}

				jsonContents, err := json.Marshal(contents)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				contentsAsString := string(jsonContents)

				return esbuild.OnLoadResult{
					Contents: &contentsAsString,
					Loader:   esbuild.LoaderJSON,
				}, nil
			})
	},
}
