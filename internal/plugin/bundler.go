package plugin

import (
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"os"
	"path"
	"path/filepath"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type esbuildResolveResult struct {
	Path        string
	SideEffects esbuild.SideEffects
	External    bool
}

var pathSep = string(filepath.Separator)

// Bundler plugin that bundles everything together.
var Bundler = esbuild.Plugin{
	Name: "bundler",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		// Resolve with esbuild. Try and avoid this call as much as possible!
		resolveWithEsbuild := func(args esbuild.OnResolveArgs, onResolveResult *esbuild.OnResolveResult) bool {
			originalPath := onResolveResult.Path

			r := build.Resolve(originalPath, esbuild.ResolveOptions{
				ResolveDir: args.ResolveDir,
				Importer:   args.Importer,
				Kind:       args.Kind,
				PluginData: types.PluginData{
					IsResolvingPath: true,
				},
			})

			if len(r.Errors) > 0 {
				// Could not resolve the path, so mark as external. This ensures we receive no
				// error, and instead allows the browser to handle the import failure.
				onResolveResult.External = true

				debug.Debug("resolveWithEsbuild:failure", originalPath, args, onResolveResult, r.Errors)

				return false
			}

			if r.SideEffects {
				onResolveResult.SideEffects = esbuild.SideEffectsTrue
			} else {
				onResolveResult.SideEffects = esbuild.SideEffectsFalse
			}

			onResolveResult.External = r.External
			onResolveResult.Path = r.Path

			debug.Debug("resolveWithEsbuild:success", originalPath, args, onResolveResult)

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

				unbundled := resolveUnbundledPrefix(&result)
				if args.With["unbundle"] == "true" {
					unbundled = true
				}

				result.Path = strings.TrimPrefix(result.Path, "node_modules/")

				gemName, gemPath, err := utils.ResolveRubyGem(result.Path)
				if err != nil {
					return result, err
				}

				if resolveWithImportMap(&result, args.ResolveDir) {
					if resolveUnbundledPrefix(&result) {
						unbundled = true
					}
				} else {
					return result, nil
				}

				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					result.PluginData = types.PluginData{ImportedFromJs: true}
				}

				ext, hasExt := utils.HasExtension(result.Path)

				if hasExt {
					if ext == ".woff" || ext == ".woff2" || ext == ".ttf" || ext == ".eot" {
						unbundled = true
					} else if utils.IsSvgImportedFromJsx(result.Path, args) {
						result.Namespace = "svgFromJsx"
					} else if utils.IsSvgImportedFromCss(result.Path, args) {
						unbundled = true
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

				if unbundled {
					result.Path = "/node_modules/" + result.Path
					result.External = true
				} else if hasExt {
					result.Path = path.Join(gemPath, utils.RemoveRubygemPrefix(result.Path, gemName))

					// In order for module resolution to be correct, we need to return a path that is within
					// the node_modules directory. If we don't, any dependencies of the rubygem will not
					// resolve correctly. But the files are actually in the gem's directory.
					// resolveArgs := cloneResolveArgs(args)
					// resolveArgs.ResolveDir = path.Join(root, "/node_modules/@rubygems", gemName)
					// result.Path = "." + strings.TrimPrefix(result.Path, gemPath)
					// ok := resolveWithEsbuild(resolveArgs, &result)
					// if !ok {
					// 	return result, nil
					// }
				}

				debug.Debug("OnResolve(@rubygems/*):end", result)

				return result, nil
			})

		// FIXME: still needed? as build specifies these directly in `buildOptions.External`
		build.OnResolve(esbuild.OnResolveOptions{Filter: `\.(gif|jpe?g|png|woff2?)$`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				debug.Debug("OnResolve(images/fonts):begin", args)

				return esbuild.OnResolveResult{
					External: true,
				}, nil
			})

		build.OnResolve(esbuild.OnResolveOptions{Filter: ".*"},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// Pass through entrypoint and paths that are currently resolving.
				if args.Kind == esbuild.ResolveEntryPoint ||
					(args.PluginData != nil && args.PluginData.(types.PluginData).IsResolvingPath) {
					return esbuild.OnResolveResult{}, nil
				}

				debug.Debug("OnResolve(.*):begin", args)

				result := esbuild.OnResolveResult{Path: args.Path}

				// Used to ensure that the result is marked as external no matter what. If this is true, it
				// will override the result.External value.
				shouldBeExternal := false
				ensureExternal := func() {
					shouldBeExternal = true
					result.External = true
				}

				unbundled := resolveUnbundledPrefix(&result)
				if args.With["unbundle"] == "true" {
					unbundled = true
				}

				if resolveWithImportMap(&result, args.ResolveDir) {
					if resolveUnbundledPrefix(&result) {
						unbundled = true
					}
				} else {
					return result, nil
				}

				isCssImportedFromJs := false
				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					isCssImportedFromJs = true
					result.PluginData = types.PluginData{ImportedFromJs: true}
				} else if utils.IsSvgImportedFromJsx(result.Path, args) {
					// We're importing an SVG file from JSX. Assigning the `svgFromJsx` namespace tells
					// the svg plugin to return the SVG as a JSX component.
					result.Namespace = "svgFromJsx"
				}

				// Ensure external if importing SVG from CSS.
				// TODO: Bundle SVG?
				if utils.IsSvgImportedFromCss(result.Path, args) {
					ensureExternal()
				}

				// Absolute path - prepend the root to prepare for resolution.
				if !shouldBeExternal && path.IsAbs(result.Path) {
					result.Path = path.Join(root, result.Path)
				}

				// If we have reached here, then the path is relative or a bare specifier.

				if shouldBeExternal {
					// It's external, so pass it through for esbuild to resolve.
					result.External = true
				} else {
					// If the path should not be external, we may still need to resolve it, as it may not
					// be a fully qualified path.

					_, hasExt := utils.HasExtension(result.Path)

					if path.IsAbs(result.Path) && hasExt {
						goto FINISH
					}

					// Try to resolve the relative path manually without needing to call esbuild.Resolve, as
					// that can get expensive. Also, by not returning the path, we let esbuild handle
					// resolving the path, which is faster and also ensures tree shaking works.
					if utils.PathIsRelative(result.Path) && hasExt {
						if isCssImportedFromJs || result.Namespace == "svgFromJsx" || unbundled {
							result.Path = path.Join(args.ResolveDir, result.Path)
						} else {
							result.Path = ""
						}
					} else {
						resolveArgs := cloneResolveArgs(args)

						if utils.IsBareModule(result.Path) {
							// If importer is a RubyGem...
							//
							// ...and that gem is NOT installed to node_modules, then change ResolveDir to the app
							// root. This ensures that bare imports are resolved relative to the app root, and not
							// the gem root, which allows us to use the app's package.json.
							//
							// ...OR that gem IS installed to node_modules, then change ResolveDir to the gem's
							// node_modules directory. This ensures that bare imports are resolved relative to the
							// gem's node_modules directory, and not the app's node_modules directory.
							gemName, _, foundGem := utils.PathIsRubyGem(args.Importer)
							if foundGem {
								nodeModulePath := filepath.Join(root, "node_modules", "@rubygems", gemName)
								_, err := os.Stat(nodeModulePath)
								if err == nil {
									realPath, err := filepath.EvalSymlinks(nodeModulePath)
									if err != nil {
										return result, err
									}

									resolveArgs.ResolveDir = realPath
								} else {
									resolveArgs.ResolveDir = root
								}
							}

							if types.Config.ExternalNodeModules {
								unbundled = true
							}
						}

						// Unqualified path! - use esbuild to resolve.
						ok := resolveWithEsbuild(resolveArgs, &result)
						if !ok {
							return result, nil
						}
					}
				}

			FINISH:

				if unbundled {
					result.External = true

					// if gemName, gemPath, foundGem := utils.PathIsRubyGem(result.Path); foundGem {
					// 	suffix := strings.TrimPrefix(result.Path, gemPath)
					// 	result.Path = "/node_modules/" + types.RubyGemsScope + gemName + suffix
					// } else {
					result.Path = strings.TrimPrefix(result.Path, root)
					// }
				}

				debug.Debug("OnResolve(.*):end", result)

				return result, nil
			})
	}}

func cloneResolveArgs(args esbuild.OnResolveArgs) esbuild.OnResolveArgs {
	return esbuild.OnResolveArgs{
		Path:       args.Path,
		Importer:   args.Importer,
		Namespace:  args.Namespace,
		ResolveDir: args.ResolveDir,
		Kind:       args.Kind,
		PluginData: args.PluginData,
		With:       args.With,
	}
}

// Strips the "unbundle:" prefix from the `result.Path`, and returns true if the prefix was found.
func resolveUnbundledPrefix(result *esbuild.OnResolveResult) bool {
	if strings.HasPrefix(result.Path, "unbundle:") {
		result.Path = strings.TrimPrefix(result.Path, "unbundle:")
		return true
	}

	return false
}

// Resolves the `result.Path` using the import map.
//
// Returns true if the path was resolved by the import map.
// Returns false if the path was not resolved by the import map.
// Returns false if the path was resolved by the import map, but is a URL.
func resolveWithImportMap(result *esbuild.OnResolveResult, resolveDir string) bool {
	resolvedImport, imErr := importmap.Resolve(result.Path, resolveDir)

	if imErr == nil {
		result.Path = resolvedImport

		if utils.IsUrl(result.Path) {
			result.External = true
			return false
		}
	} else {
		result.PluginName = "importmap"
		result.Errors = []esbuild.Message{{
			Text:     imErr.Error(),
			Location: &esbuild.Location{File: importmap.FilePath()},
			Detail:   imErr,
		}}

		return false
	}

	return true
}
