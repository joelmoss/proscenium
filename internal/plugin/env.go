package plugin

import (
	"os"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

// Export named environment variables as default module. For security reasons, it is not possible to
// access environment variables that are not explicitly named. Will export `undefined` if the env
// variable is not defined.
//
// Example:
//
//	import RAILS_ENV from '@proscenium/env/RAILS_ENV';
var Env = esbuild.Plugin{
	Name: "Env",
	Setup: func(build esbuild.PluginBuild) {
		build.OnResolve(esbuild.OnResolveOptions{Filter: `^@proscenium\/env\/(.+)$`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				paths := strings.Split(args.Path, "/")

				return esbuild.OnResolveResult{
					Path:      paths[len(paths)-1],
					Namespace: "env",
				}, nil
			})

		build.OnLoad(esbuild.OnLoadOptions{Filter: `.*`, Namespace: "env"},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				contents := ""
				value, ok := os.LookupEnv(args.Path)
				if ok {
					contents = "export default '" + value + "';"
				} else {
					contents = "export default undefined;"
				}

				return esbuild.OnLoadResult{
					Contents: &contents,
					Loader:   esbuild.LoaderJS,
				}, nil
			})
	},
}
