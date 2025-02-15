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

// Bundler plugin that does not bundles everything together.
var Bundless = esbuild.Plugin{
	Name: "bundless",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		build.OnResolve(esbuild.OnResolveOptions{Filter: ".*"},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// Pass through paths that are currently resolving.
				if args.PluginData != nil && args.PluginData.(types.PluginData).IsResolvingPath {
					return esbuild.OnResolveResult{}, nil
				}

				// pp.Println("[bundless] args:", args)

				// Should we use esbuild to resolve this path?
				useResolve := false

				rubyGem := ""

				// Path that is resolved from a Rails engine.
				pathFromEngine := ""

				// The root path of the resolved Rails engine.
				resolvedEnginePath := ""

				// The key of the resolved Rails engine.
				resolvedEngineKey := ""

				result := esbuild.OnResolveResult{
					External: true,
					Path:     strings.TrimPrefix(args.Path, "unbundle:"),
				}

				// Entry points should usually be passed through as-is, so esbuild can handle them. However,
				// we do need to resolve paths that are from any registered Rails engines.
				if args.Kind == esbuild.ResolveEntryPoint {
					// Handle Ruby gems.
					for key, value := range types.Config.Engines {
						prefix := key + pathSep
						if strings.HasPrefix(result.Path, prefix) {
							resolvedEngineKey = key
							resolvedEnginePath = value
							pathFromEngine = filepath.Join(value, strings.TrimPrefix(result.Path, prefix))
							break
						}
					}

					if pathFromEngine == "" {
						// Not in an engine, so pass through entry point as-is.
						return esbuild.OnResolveResult{}, nil
					}

					result.External = false
				} else {
					// Handle non-entrypoint Ruby gems.
					for key, value := range types.Config.Engines {
						prefix := pathSep + key + pathSep
						if strings.HasPrefix(result.Path, prefix) {
							resolvedEngineKey = key
							resolvedEnginePath = value
							pathFromEngine = filepath.Join(value, strings.TrimPrefix(result.Path, prefix))
							break
						}
					}
				}

				if pathFromEngine != "" {
					result.Path = pathFromEngine
				} else {
					if resolvedPath, imErr := importmap.Resolve(result.Path, args.ResolveDir); imErr != nil {
						result.PluginName = "importmap"
						result.Errors = []esbuild.Message{{
							Text:     imErr.Error(),
							Location: &esbuild.Location{File: importmap.FilePath()},
							Detail:   imErr,
						}}
						return result, nil
					} else {
						result.Path = resolvedPath

						if strings.HasPrefix(result.Path, "unbundle:") {
							result.Path = strings.TrimPrefix(result.Path, "unbundle:")
						}
					}

					if utils.IsUrl(result.Path) {
						goto FINISH
					}

					if path.IsAbs(result.Path) {
						result.Path = path.Join(root, result.Path)
					} else if utils.PathIsRelative(result.Path) {
						result.Path = path.Join(args.ResolveDir, result.Path)
					}
				}

				// isCssImportedFromJs := false
				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					// isCssImportedFromJs = true
					result.External = false
					result.PluginData = types.PluginData{ImportedFromJs: true}
				}

				if utils.IsRubyGem(result.Path) {
					gemName, err := utils.ResolveRubyGem(result.Path)
					if err != nil {
						return result, err
					}

					if filepath.Ext(result.Path) == "" {
						suffix := strings.TrimPrefix(result.Path, types.RubyGemsScope+gemName)
						result.Path = filepath.Join(types.Config.RubyGems[gemName], suffix)
						useResolve = true
						rubyGem = gemName
					} else {
						result.Path = "/node_modules/" + result.Path
						goto FINISH
					}
				}

				if utils.IsBareModule(result.Path) || filepath.Ext(result.Path) == "" {
					useResolve = true
				}

				if useResolve {
					resolveOpts := esbuild.ResolveOptions{
						ResolveDir: args.ResolveDir,
						Importer:   args.Importer,
						Kind:       args.Kind,
						PluginData: types.PluginData{
							IsResolvingPath: true,
						},
					}

					if utils.IsBareModule(result.Path) {
						// If importer is a Rails engine, then change ResolveDir to the app root. This ensures
						// that bare imports are resolved relative to the app root, and not the engine root.
						// Which allows us to use the app's package.json and node_modules dir.
						for _, value := range types.Config.Engines {
							if strings.HasPrefix(args.Importer, value+pathSep) {
								resolveOpts.ResolveDir = root
								break
							}
						}
					}

					r := build.Resolve(result.Path, resolveOpts)

					result.Path = r.Path
					result.Errors = r.Errors
					result.Warnings = r.Warnings

					if r.SideEffects {
						result.SideEffects = esbuild.SideEffectsTrue
					} else {
						result.SideEffects = esbuild.SideEffectsFalse
					}
				}

			FINISH:

				if rubyGem != "" {
					suffix := strings.TrimPrefix(result.Path, types.Config.RubyGems[rubyGem])
					result.Path = "/node_modules/" + types.RubyGemsScope + rubyGem + suffix
				}

				// Only entrypoints must be an absolute path.
				if args.Kind != esbuild.ResolveEntryPoint && result.Path != "" {
					if resolvedEnginePath != "" && resolvedEngineKey != "" {
						result.Path = filepath.Join(pathSep, resolvedEngineKey, strings.TrimPrefix(result.Path, resolvedEnginePath))
					} else {
						newPath := ""

						for key, value := range types.Config.Engines {
							if strings.HasPrefix(result.Path, value+pathSep) {
								newPath = filepath.Join(pathSep, key, strings.TrimPrefix(result.Path, value))
								break
							}
						}

						if newPath != "" {
							result.Path = newPath
						} else if result.External && strings.HasPrefix(result.Path, root) {
							result.Path = strings.TrimPrefix(result.Path, root)
						}
					}
				}

				// pp.Println("[bundless] result:", result)

				return result, nil
			})
	}}
