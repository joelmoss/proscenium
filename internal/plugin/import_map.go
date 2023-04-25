package plugin

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

func ImportMap(options types.PluginOptions) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "import_map",
		Setup: func(build esbuild.PluginBuild) {
			build.OnResolve(esbuild.OnResolveOptions{Filter: `.*`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					// Ignore entry points.
					if args.Kind == esbuild.ResolveEntryPoint {
						return esbuild.OnResolveResult{}, nil
					}

					resolvedImport, matched := importmap.Resolve(args.Path, args.ResolveDir, options.ImportMap)
					if matched {
						return esbuild.OnResolveResult{
							Path:     resolvedImport,
							External: true,
						}, nil
					}

					return esbuild.OnResolveResult{}, nil
				})
		},
	}
}
