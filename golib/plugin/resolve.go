package golib_plugin

import (
	"github.com/evanw/esbuild/pkg/api"
)

var Resolve = api.Plugin{
	Name: "resolve",
	Setup: func(build api.PluginBuild) {
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
