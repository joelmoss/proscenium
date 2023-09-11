package plugin

import (
	"joelmoss/proscenium/internal/utils"
	"os"
	"path"
	"runtime"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

var Libs = esbuild.Plugin{
	Name: "libs",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir
		_, filename, _, _ := runtime.Caller(0)
		libDir := path.Join(path.Dir(filename), "..", "..", "lib", "proscenium", "libs")

		build.OnResolve(esbuild.OnResolveOptions{Filter: `^@proscenium/`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				return esbuild.OnResolveResult{
					Path:      args.Path,
					Namespace: "libs",
				}, nil
			})

		build.OnLoad(esbuild.OnLoadOptions{Filter: `\.*`, Namespace: "libs"},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				filename := strings.TrimPrefix(args.Path, "@proscenium/")
				if !utils.HasExtension(filename) {
					filename = filename + ".js"
				}

				filepath := path.Join(libDir, filename)
				data, err := os.ReadFile(filepath)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				contents := string(data)

				return esbuild.OnLoadResult{
					Contents:   &contents,
					Loader:     esbuild.LoaderJS,
					ResolveDir: root,
				}, nil
			})
	},
}
