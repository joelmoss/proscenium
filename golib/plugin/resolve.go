package golib_plugin

import (
	"github.com/evanw/esbuild/pkg/api"
	"github.com/k0kubun/pp/v3"
)

func Resolve(options PluginOptions) api.Plugin {
	pp.Print(options)

	return api.Plugin{
		Name: "resolve",
		Setup: func(build api.PluginBuild) {
			build.OnResolve(api.OnResolveOptions{Filter: `.*`},
				func(args api.OnResolveArgs) (api.OnResolveResult, error) {
					pp.Print(options.ImportMap.Imports)

					return api.OnResolveResult{
						Path:     args.Path,
						External: true,
					}, nil
				})
		},
	}
}
