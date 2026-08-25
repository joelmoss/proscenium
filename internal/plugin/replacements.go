package plugin

import (
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

func Replacements(cfg *types.ConfigT) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "replacements",
		Setup: func(build esbuild.PluginBuild) {
			build.OnLoad(
				esbuild.OnLoadOptions{Filter: ".*", Namespace: "replacement"},
				func(args esbuild.OnLoadArgs) (ret esbuild.OnLoadResult, err error) {
					debug.Debug(cfg.Debug, "OnLoad", args.Path)

					contents := string(args.PluginData.([]byte))
					return esbuild.OnLoadResult{Contents: &contents, Loader: esbuild.LoaderJS}, nil
				},
			)
		},
	}
}
