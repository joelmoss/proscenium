package plugin

import (
	"joelmoss/proscenium/internal/importmap"
	"path"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type PluginData = struct {
	isResolvingPath bool
}

func Resolve() esbuild.Plugin {
	return esbuild.Plugin{
		Name: "resolve",
		Setup: func(build esbuild.PluginBuild) {
			root := build.InitialOptions.AbsWorkingDir

			build.OnResolve(esbuild.OnResolveOptions{Filter: `.*`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					// Ignore entry points.
					if args.Kind == esbuild.ResolveEntryPoint {
						return esbuild.OnResolveResult{}, nil
					}

					// Ignore imports that currently resolving.
					if args.PluginData != nil && args.PluginData.(PluginData).isResolvingPath {
						return esbuild.OnResolveResult{}, nil
					}

					// result := resolver.Resolve(args, options.ImportMap, root)

					if importmap.Contents.IsParsed {
						// Look for a match in the import map
						resolvedImport, matched := importmap.Resolve(args.Path, args.ResolveDir, root)
						if matched {
							args.Path = resolvedImport
						}
					} else {
						// Absolute path - append to current working dir. This enables absolute path imports
						// (eg, import '/lib/foo').
						if path.IsAbs(args.Path) {
							args.Path = path.Join(root, args.Path)
						}
					}

					// Resolve with esbuild
					// result := build.Resolve(pathToResolve, esbuild.ResolveOptions{
					// 	ResolveDir: args.ResolveDir,
					// 	Importer:   args.Importer,
					// 	Kind:       esbuild.ResolveJSImportStatement,
					// 	PluginData: PluginData{isResolvingPath: true},
					// })

					// pp.Println(pathToResolve, esbuild.ResolveOptions{
					// 	ResolveDir: args.ResolveDir,
					// 	Importer:   args.Importer,
					// 	Kind:       esbuild.ResolveJSImportStatement,
					// 	PluginData: PluginData{isResolvingPath: true},
					// }, result)

					// if len(result.Errors) > 0 {
					// 	return esbuild.OnResolveResult{Errors: result.Errors}, nil
					// }

					// Make sure the path is relative to the root.
					args.Path = strings.TrimPrefix(args.Path, root)

					return esbuild.OnResolveResult{Path: args.Path, External: true}, nil
				})
		},
	}
}
