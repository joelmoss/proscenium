package plugin

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"path"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type PluginData = struct {
	isResolvingPath bool
}

func Resolve(options types.PluginOptions) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "resolve",
		Setup: func(build esbuild.PluginBuild) {
			root := build.InitialOptions.AbsWorkingDir

			build.OnResolve(esbuild.OnResolveOptions{Filter: `.*`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					if args.Kind == esbuild.ResolveEntryPoint {
						return esbuild.OnResolveResult{}, nil
					}

					if args.PluginData != nil && args.PluginData.(PluginData).isResolvingPath {
						return esbuild.OnResolveResult{}, nil
					}

					// result := internal.Resolve(args, options.ImportMap, root)

					if options.ImportMap != nil {
						// Look for a match in the import map
						base := strings.TrimPrefix(args.Importer, root)
						resolvedImport, matched := importmap.ResolvePathFromImportMap(args.Path, options.ImportMap, base)
						if matched {
							return esbuild.OnResolveResult{
								Path:     resolvedImport,
								External: true,
							}, nil
						}
					}

					pathToResolve := args.Path

					// Absolute path - append to current working dir. This enabled absolute path imports
					// (eg, import '/lib/foo').
					if strings.HasPrefix(pathToResolve, "/") {
						pathToResolve = path.Join(root, pathToResolve)
					}

					// Resolve with esbuild
					result := build.Resolve(pathToResolve, esbuild.ResolveOptions{
						ResolveDir: args.ResolveDir,
						Importer:   args.Importer,
						Kind:       esbuild.ResolveJSImportStatement,
						PluginData: PluginData{isResolvingPath: true},
					})

					// pp.Println(pathToResolve, esbuild.ResolveOptions{
					// 	ResolveDir: args.ResolveDir,
					// 	Importer:   args.Importer,
					// 	Kind:       esbuild.ResolveJSImportStatement,
					// 	PluginData: PluginData{isResolvingPath: true},
					// }, result)

					if len(result.Errors) > 0 {
						return esbuild.OnResolveResult{Errors: result.Errors}, nil
					}

					// Path is external, so make sure it is relative to the root.
					relativePath := strings.TrimPrefix(result.Path, root)

					return esbuild.OnResolveResult{Path: relativePath, External: true}, nil
				})
		},
	}
}
