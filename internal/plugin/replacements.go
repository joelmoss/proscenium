package plugin

import (
	"joelmoss/proscenium/internal/debug"

	esbuild "github.com/ije/esbuild-internal/api"
)

var Replacements = esbuild.Plugin{
	Name: "replacements",
	Setup: func(build esbuild.PluginBuild) {
		build.OnLoad(
			esbuild.OnLoadOptions{Filter: ".*", Namespace: "replacement"},
			func(args esbuild.OnLoadArgs) (ret esbuild.OnLoadResult, err error) {
				debug.Debug("OnLoad", args.Path)

				contents := string(args.PluginData.([]byte))
				return esbuild.OnLoadResult{Contents: &contents, Loader: esbuild.LoaderJS}, nil
			},
		)
	},
}
