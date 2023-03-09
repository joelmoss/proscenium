package plugin

import (
	"joelmoss/proscenium/golib/utils"

	"github.com/evanw/esbuild/pkg/api"
)

func Resolve(options PluginOptions) api.Plugin {
	return api.Plugin{
		Name: "resolve",
		Setup: func(build api.PluginBuild) {
			build.OnResolve(api.OnResolveOptions{Filter: `.*`},
				func(args api.OnResolveArgs) (api.OnResolveResult, error) {
					if args.Kind == api.ResolveEntryPoint {
						return api.OnResolveResult{}, nil
					}

					result := utils.Resolve(&args, options.ImportMap)

					return result, nil
				})
		},
	}
}
