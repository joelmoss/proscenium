package plugin

import (
	"joelmoss/proscenium/internal/css"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

func Css() esbuild.Plugin {
	return esbuild.Plugin{
		Name: "Css",
		Setup: func(build esbuild.PluginBuild) {
			root := build.InitialOptions.AbsWorkingDir

			build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
				func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
					contents, err := css.ParseCssFile(args.Path, root)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					return esbuild.OnLoadResult{
						Contents: &contents,
						Loader:   esbuild.LoaderCSS,
					}, nil
				})
		},
	}
}
