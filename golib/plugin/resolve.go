package plugin

import (
	"joelmoss/proscenium/golib/api"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

func Resolve(options api.PluginOptions) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "resolve",
		Setup: func(build esbuild.PluginBuild) {
			build.OnResolve(esbuild.OnResolveOptions{Filter: `.*`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					if args.Kind == esbuild.ResolveEntryPoint {
						return esbuild.OnResolveResult{}, nil
					}

					result := api.Resolve(&args, options.ImportMap)

					return result, nil
				})
		},
	}
}
