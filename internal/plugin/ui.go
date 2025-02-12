package plugin

import (
	"joelmoss/proscenium/internal/types"
	"path"
	"path/filepath"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

var Ui = esbuild.Plugin{
	Name: "ui",
	Setup: func(build esbuild.PluginBuild) {
		var uiDir = path.Join(types.Config.GemPath, "lib", "proscenium", "ui")

		resolvePath := func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
			args.Path = path.Join(uiDir, args.Path)

			if filepath.Ext(args.Path) != "" {
				// We have a full file path with extension, so no need to resolve with esbuild. Instead
				// just pass through as-is.
				return esbuild.OnResolveResult{
					Path: args.Path,
				}, nil
			}

			r := build.Resolve(args.Path, esbuild.ResolveOptions{
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

			if !types.Config.Bundle && args.Kind != esbuild.ResolveEntryPoint {
				r.External = true
				r.Path = strings.TrimPrefix(r.Path, uiDir)
				r.Path = path.Join("/proscenium", r.Path)
			}

			return esbuild.OnResolveResult{
				Path:        r.Path,
				External:    r.External,
				Errors:      r.Errors,
				Warnings:    r.Warnings,
				SideEffects: sideEffects,
			}, nil
		}

		build.OnResolve(esbuild.OnResolveOptions{Filter: `^proscenium/`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				args.Path = strings.TrimPrefix(args.Path, "proscenium/")
				return resolvePath(args)
			})
	}}
