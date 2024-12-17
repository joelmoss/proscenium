package plugin

import (
	"joelmoss/proscenium/internal/types"
	"path"
	"path/filepath"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

var Libs = esbuild.Plugin{
	Name: "libs",
	Setup: func(build esbuild.PluginBuild) {
		libDir := path.Join(types.Config.GemPath, "lib", "proscenium", "libs")

		build.OnResolve(esbuild.OnResolveOptions{Filter: `^@proscenium/`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				pathToResolve := path.Join(libDir, strings.TrimPrefix(args.Path, "@proscenium/"))

				if filepath.Ext(pathToResolve) != "" {
					// We have a full file path with extension, so no need to resolve with esbuild. Instead
					// just pass through as-is.
					return esbuild.OnResolveResult{
						Path: pathToResolve,
					}, nil
				}

				r := build.Resolve(pathToResolve, esbuild.ResolveOptions{
					ResolveDir: args.ResolveDir,
					Importer:   args.Importer,
					Kind:       args.Kind,
					PluginData: types.PluginData{
						IsResolvingPath: true,
					},
				})

				sideEffects := esbuild.SideEffectsFalse
				if r.SideEffects {
					sideEffects = esbuild.SideEffectsTrue
				}

				return esbuild.OnResolveResult{
					Path:        r.Path,
					External:    r.External,
					Errors:      r.Errors,
					Warnings:    r.Warnings,
					SideEffects: sideEffects,
				}, nil
			})
	}}
