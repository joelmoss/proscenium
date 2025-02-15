package plugin

import (
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path"
	"path/filepath"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

// Bundler plugin that does not bundles everything together.
var Bundless = esbuild.Plugin{
	Name: "bundless",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		// Resolve with esbuild. Try and avoid this call as much as possible!
		resolveWithEsbuild := func(args esbuild.OnResolveArgs, onResolveResult *esbuild.OnResolveResult) bool {
			r := build.Resolve(onResolveResult.Path, esbuild.ResolveOptions{
				ResolveDir: args.ResolveDir,
				Importer:   args.Importer,
				Kind:       args.Kind,
				PluginData: types.PluginData{
					IsResolvingPath: true,
				},
			})

			onResolveResult.Path = r.Path
			onResolveResult.Errors = r.Errors
			onResolveResult.Warnings = r.Warnings

			if r.SideEffects {
				onResolveResult.SideEffects = esbuild.SideEffectsTrue
			} else {
				onResolveResult.SideEffects = esbuild.SideEffectsFalse
			}

			debug.Debug("resolveWithEsbuild", args, onResolveResult)

			return true
		}

		build.OnResolve(esbuild.OnResolveOptions{Filter: `^(unbundle:)?(node_modules/)?@rubygems/`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// Pass through paths that are currently resolving.
				if args.PluginData != nil && args.PluginData.(types.PluginData).IsResolvingPath {
					return esbuild.OnResolveResult{}, nil
				}

				debug.Debug("OnResolve(@rubygems/*):begin", args)

				result := esbuild.OnResolveResult{Path: args.Path}
				resolveUnbundledPrefix(&result)
				result.Path = strings.TrimPrefix(result.Path, "node_modules/")

				gemName, gemPath, err := utils.ResolveRubyGem(result.Path)
				if err != nil {
					return result, err
				}

				if resolveWithImportMap(&result, args.ResolveDir) {
					resolveUnbundledPrefix(&result)
				} else {
					return result, nil
				}

				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					result.PluginData = types.PluginData{ImportedFromJs: true}
				}

				// If the path is an entrypoint, then it must be an absolute fileystem path.
				if args.Kind == esbuild.ResolveEntryPoint {
					result.Path = path.Join(gemPath, utils.RemoveRubygemPrefix(result.Path, gemName))
				} else {
					if _, hasExt := utils.HasExtension(result.Path); hasExt {
						// FIXME: needed?
						if utils.IsSvgImportedFromJsx(result.Path, args) {
							result.Namespace = "svgFromJsx"
						}
					} else {
						// == Unqualified path! - use esbuild to resolve.

						resolveArgs := cloneResolveArgs(args)
						resolveArgs.ResolveDir = gemPath

						suffix := utils.RemoveRubygemPrefix(result.Path, gemName)
						result.Path = filepath.Join(resolveArgs.ResolveDir, suffix)

						ok := resolveWithEsbuild(resolveArgs, &result)
						if !ok {
							return result, nil
						}
					}

					if strings.HasPrefix(result.Path, types.RubyGemsScope+gemName) {
						result.Path = "/node_modules/" + result.Path
					} else {
						suffix := strings.TrimPrefix(result.Path, gemPath)
						result.Path = "/node_modules/" + types.RubyGemsScope + gemName + suffix
					}

					result.External = true
				}

				debug.Debug("OnResolve(@rubygems/*):end", result)

				return result, nil
			})

		build.OnResolve(esbuild.OnResolveOptions{Filter: ".*"},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// Pass through entrypoint and paths that are currently resolving.
				if args.Kind == esbuild.ResolveEntryPoint ||
					(args.PluginData != nil && args.PluginData.(types.PluginData).IsResolvingPath) {
					return esbuild.OnResolveResult{}, nil
				}

				debug.Debug("OnResolve(.*):begin", args)

				result := esbuild.OnResolveResult{Path: args.Path, External: true}

				resolveUnbundledPrefix(&result)
				if resolveWithImportMap(&result, args.ResolveDir) {
					resolveUnbundledPrefix(&result)
				} else {
					return result, nil
				}

				_, hasExt := utils.HasExtension(result.Path)

				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					//
					// TODO: We're not bundling, but the import may want the CSS as a JS object of class
					// names. (CSS module), or a constructable stylesheet. We need to handle this case.
					result.PluginData = types.PluginData{ImportedFromJs: true}
				}

				if utils.IsUrl(result.Path) {
					goto FINISH
				}

				if filepath.IsAbs(result.Path) {
					if hasExt {
						// Absolute path and extension, so assume this is an app relative path, and return as is.
						goto FINISH
					} else {
						result.Path = path.Join(root, result.Path)
					}
				}

				// Try to resolve the relative path manually without needing to call esbuild.Resolve, as
				// that can get expensive.
				if utils.PathIsRelative(result.Path) && hasExt {
					result.Path = path.Join(args.ResolveDir, result.Path)
				} else {
					resolveArgs := cloneResolveArgs(args)

					if utils.IsBareModule(result.Path) {
						// If importer is a RubyGem, then change ResolveDir to the app root. This ensures
						// that bare imports are resolved relative to the app root, and not the gem root.
						// Which allows us to use the app's package.json and node_modules dir.
						_, _, foundGem := utils.PathIsRubyGem(args.Importer)
						if foundGem {
							resolveArgs.ResolveDir = root
						}
					}

					// Unqualified path! - use esbuild to resolve.
					ok := resolveWithEsbuild(resolveArgs, &result)
					if !ok {
						return result, nil
					}
				}

			FINISH:

				if gemPath, ok := utils.RubyGemPathToUrlPath(result.Path); ok {
					result.Path = gemPath
				} else if newPath, ok := rootPathToUrlPath(result.Path); ok {
					result.Path = newPath
				}

				debug.Debug("OnResolve:end", result)

				return result, nil
			})
	}}

// Converts an absolute file system path that begins with the root, to a URL path.
func rootPathToUrlPath(fsPath string) (urlPath string, found bool) {
	if strings.HasPrefix(fsPath, types.Config.RootPath) {
		return strings.TrimPrefix(fsPath, types.Config.RootPath), true
	}

	return "", false
}
