package plugin

import (
	"joelmoss/proscenium/golib/internal"

	esbuild "github.com/evanw/esbuild/pkg/api"
	"github.com/k0kubun/pp/v3"
)

func ImportMap(options internal.PluginOptions) esbuild.Plugin {
	pp.Print(options)

	return esbuild.Plugin{
		Name: "importMap",
		Setup: func(build esbuild.PluginBuild) {
			// build.OnResolve(api.OnResolveOptions{Filter: `\.svg$`},
			// 	func(args api.OnResolveArgs) (api.OnResolveResult, error) {
			// 		if args.Kind == api.ResolveJSImportStatement && strings.HasSuffix(args.Importer, ".jsx") {
			// 			return api.OnResolveResult{
			// 				Path:      filepath.Join(publicPath, args.Path),
			// 				Namespace: "svg",
			// 			}, nil
			// 		} else {
			// 			return api.OnResolveResult{
			// 				Path:     args.Path,
			// 				External: true,
			// 			}, nil
			// 		}
			// 	})
		},
	}
}
