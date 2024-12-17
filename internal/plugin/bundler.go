package plugin

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
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
		resolveWithEsbuild := func(pathToResolve string, args esbuild.OnResolveArgs) (esbuildResolveResult, bool) {
			result := esbuildResolveResult{}

			r := build.Resolve(pathToResolve, esbuild.ResolveOptions{
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
				result.External = true
				return result, false
			}

			if r.SideEffects {
				result.SideEffects = esbuild.SideEffectsTrue
			} else {
				result.SideEffects = esbuild.SideEffectsFalse
			}

			result.External = r.External
			result.Path = r.Path

			// pp.Println("[1] resolveWithEsbuild", pathToResolve, args, result)

			return result, true
		}

		// File types which should be external.
		build.OnResolve(esbuild.OnResolveOptions{Filter: `\.(gif|jpe?g|png|woff2?)$`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				return esbuild.OnResolveResult{
					External: true,
				}, nil
			})

		build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?://(.+)\.svg$`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// SVG files imported from JSX should be downloaded and bundled as JSX with the svgFromJsx
				// namespace.
				if utils.IsImportedFromJsx(args.Path, args) {
					return esbuild.OnResolveResult{
						Path:      args.Path,
						Namespace: "svgFromJsx",
					}, nil
				}

				// URL's are external.
				return esbuild.OnResolveResult{
					Path:     args.Path,
					External: true,
				}, nil
			})

		// Mark all paths starting with "http://" or "https://" as external
		build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?://`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				return esbuild.OnResolveResult{
					Path:     args.Path,
					External: true,
				}, nil
			})

		build.OnResolve(esbuild.OnResolveOptions{Filter: ".*"},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// Pass through paths that are currently resolving.
				if args.PluginData != nil && args.PluginData.(types.PluginData).IsResolvingPath {
					return esbuild.OnResolveResult{}, nil
				}

				unbundled := false
				isEngine := false
				result := esbuild.OnResolveResult{}

				// Pass through entry points.
				if args.Kind == esbuild.ResolveEntryPoint {
					// Handle Ruby gems.
					for key, value := range types.Config.Engines {
						prefix := key + pathSep
						if strings.HasPrefix(args.Path, prefix) {
							result.Path = filepath.Join(value, strings.TrimPrefix(args.Path, prefix))
							isEngine = true
							break
						}
					}

					if result.Path == "" {
						return esbuild.OnResolveResult{}, nil
					}
				} else {
					// Handle non-entrypoint Ruby gems.
					for key, value := range types.Config.Engines {
						prefix := pathSep + key + pathSep
						if strings.HasPrefix(args.Path, prefix) {
							result.Path = filepath.Join(value, strings.TrimPrefix(args.Path, prefix))
							isEngine = true
							break
						}
					}
				}

				if result.Path == "" {
					result.Path = args.Path
				}

				// Used to ensure that the result is marked as external no matter what. If this is true, it
				// will override the result.External value.
				shouldBeExternal := false
				ensureExternal := func() {
					shouldBeExternal = true
					result.External = true
				}

				if strings.HasPrefix(result.Path, "unbundle:") {
					result.Path = strings.TrimPrefix(result.Path, "unbundle:")
					unbundled = true
				}

				resolvedImport, imErr := importmap.Resolve(result.Path, args.ResolveDir)
				if imErr != nil {
					result.PluginName = "importmap"
					result.Errors = []esbuild.Message{{
						Text:     imErr.Error(),
						Location: &esbuild.Location{File: importmap.FilePath()},
						Detail:   imErr,
					}}
					return result, nil
				} else {
					result.Path = resolvedImport

					if utils.IsUrl(result.Path) {
						result.External = true
						return result, nil
					}

					if strings.HasPrefix(result.Path, "unbundle:") {
						result.Path = strings.TrimPrefix(result.Path, "unbundle:")
						unbundled = true
					}
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
					if isEngine {
						result.Path = args.Path
					}
					ensureExternal()
				}

				// Absolute path - prepend the root to prepare for resolution.
				if !isEngine && path.IsAbs(result.Path) && !shouldBeExternal {
					result.Path = path.Join(root, result.Path)
				}

				// If we have reached here, then the path is relative or a bare specifier.

				if shouldBeExternal {
					// It's external, so pass it through for esbuild to resolve.
					result.External = true
				} else {
					// If the path should not be external, then we may still need to resolve it, as it may not
					// be a fully qualified path.

					if path.IsAbs(result.Path) && filepath.Ext(result.Path) != "" {
						// If the path is absolute, then we can just return it as is. However, it must be a
						// fully qualified path with a file extension. We can then return it as is. Othwerwise,
						// we need to resolve it.
						if unbundled {
							result.Path = strings.TrimPrefix(result.Path, root)
							result.External = true
						}

						return result, nil
					}

					// Try to resolve the relative path manually without needing to call esbuild.Resolve, as
					// that can get expensive. Also, by not returning the path, we let esbuild handle
					// resolving the path, which is faster and also ensures tree shaking works.
					if utils.PathIsRelative(result.Path) {
						if isCssImportedFromJs || result.Namespace == "svgFromJsx" {
							result.Path = path.Join(args.ResolveDir, result.Path)
						} else if unbundled {
							result.Path = path.Join(args.ResolveDir, result.Path)
						} else {
							result.Path = ""
						}
					} else {
						if utils.IsBareModule(result.Path) {
							// If importer is a Rails engine, then change ResolveDir to the app root. This ensures
							// that bare imports are resolved relative to the app root, and not the engine root.
							// Which allows us to use the app's package.json and node_modules dir.
							for _, value := range types.Config.Engines {
								if strings.HasPrefix(args.Importer, value+pathSep) {
									args.ResolveDir = root
									break
								}
							}
						}

						// Unqualified path! - use esbuild to resolve.
						resolveResult, ok := resolveWithEsbuild(result.Path, args)

						result.Path = resolveResult.Path
						result.External = resolveResult.External
						result.SideEffects = resolveResult.SideEffects

						if !ok {
							return result, nil
						}
					}
				}

				if unbundled {
					result.Path = strings.TrimPrefix(result.Path, root)
					result.External = true
				}

				return result, nil
			})
	}}
