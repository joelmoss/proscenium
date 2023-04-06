package plugin

import (
	"joelmoss/proscenium/internal/css"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

func Css() esbuild.Plugin {
	return esbuild.Plugin{
		Name: "Css",
		Setup: func(build esbuild.PluginBuild) {
			build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
				func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
					contents, err := css.ParseCssFile(args.Path)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					return esbuild.OnLoadResult{
						Contents: &contents,
					}, nil
				})
		},
	}
}
