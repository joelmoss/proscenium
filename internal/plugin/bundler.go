package plugin

import (
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/replacements"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"os"
	"path"
	"path/filepath"
	"strings"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

// Bundler plugin that bundles everything together.
func Bundler(cfg *types.ConfigT) esbuild.Plugin {
	return esbuild.Plugin{
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

					debug.Debug(cfg.Debug, "resolveWithEsbuild:failure", originalPath, args, onResolveResult, r.Errors)

					return false
				}

				if r.SideEffects {
					onResolveResult.SideEffects = esbuild.SideEffectsTrue
				} else {
					onResolveResult.SideEffects = esbuild.SideEffectsFalse
				}

				onResolveResult.External = r.External
				onResolveResult.Path = r.Path

				debug.Debug(cfg.Debug, "resolveWithEsbuild:success", originalPath, args, onResolveResult)

				return true
			}

			// The one definition of how an `@rubygems/` path resolves. Called from the top-level
			// handler below, and from the aliased-path branch of the catch-all handler, which used
			// to carry a hand-copied version of this that had drifted in four ways - see the commit
			// that extracted it. Mutates `result`; a nil error means "resolved, keep going".
			resolveRubygemPath := func(args esbuild.OnResolveArgs, result *esbuild.OnResolveResult) error {
				unbundled := resolveUnbundledPrefix(result)
				if args.With["unbundle"] == "true" {
					unbundled = true
				}

				result.Path = strings.TrimPrefix(result.Path, "node_modules/")

				// The alias is resolved BEFORE the gem, because it can name a different gem. The
				// other order left `gemName`/`gemPath` describing the pre-alias gem, and joining
				// that root with the post-alias suffix built a path belonging to neither -
				// `<gem2-root>/@rubygems/gem1/lib/gem1/gem1.js`.
				if aliasedPath, exists := utils.HasAlias(result.Path, cfg); exists {
					debug.Debug(cfg.Debug, "resolveRubygemPath:alias", result.Path, aliasedPath)
					result.Path = aliasedPath

					// Only ever raises the flag. Assigning it here cleared an `unbundle:` prefix or
					// import attribute from before the alias, and esbuild then rejected the build
					// for an attribute nothing had consumed.
					if resolveUnbundledPrefix(result) {
						unbundled = true
					}

					result.Path = strings.TrimPrefix(result.Path, "node_modules/")
				}

				gemName, gemPath, err := utils.ResolveRubyGem(result.Path, cfg)
				if err != nil {
					return err
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

					if ok := resolveWithEsbuild(resolveArgs, result); !ok {
						// `resolveWithEsbuild` has marked the result external so the browser reports the
						// failure. Nothing below applies to a path it could not resolve.
						return nil
					}
				}

				if unbundled {
					result.External = true

					if urlPath, ok := utils.RubyGemPathToUrlPath(result.Path, cfg); ok {
						result.Path = urlPath
					} else {
						result.Path = "/node_modules/" + result.Path
					}
				} else if hasExt {
					result.Path = filepath.Join(gemPath, utils.RemoveRubygemPrefix(result.Path, gemName))
				}

				return nil
			}

			build.OnResolve(esbuild.OnResolveOptions{Filter: `^(unbundle:)?(node_modules/)?@rubygems/`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					// Pass through paths that are currently resolving.
					if args.PluginData != nil && args.PluginData.(types.PluginData).IsResolvingPath {
						return esbuild.OnResolveResult{}, nil
					}

					debug.Debug(cfg.Debug, "OnResolve(@rubygems/*):begin", args)

					result := esbuild.OnResolveResult{Path: args.Path}

					if err := resolveRubygemPath(args, &result); err != nil {
						return result, err
					}

					debug.Debug(cfg.Debug, "OnResolve(@rubygems/*):end", result)

					return result, nil
				})

			// FIXME: still needed? as build specifies these directly in `buildOptions.External`
			build.OnResolve(esbuild.OnResolveOptions{Filter: `\.(gif|jpe?g|png|woff2?)$`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					debug.Debug(cfg.Debug, "OnResolve(images/fonts):begin", args)

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

					debug.Debug(cfg.Debug, "OnResolve(.*):begin", args)

					result := esbuild.OnResolveResult{Path: args.Path}

					// Used to ensure that the result is marked as external no matter what. If this is true, it
					// will override the result.External value.
					shouldBeExternal := false
					ensureExternal := func() {
						shouldBeExternal = true
						result.External = true
					}

					unbundled := false
					isCssImportedFromJs := false

					// Map aliases for only bare paths. Aliases for all other paths are handled at the end -
					// once we have a full absolute path.
					if utils.IsBareModule(result.Path) {
						if aliasedPath, exists := utils.HasAlias(result.Path, cfg); exists {
							debug.Debug(cfg.Debug, "OnResolve(.*):aliasBefore", result.Path, aliasedPath)
							result.Path = aliasedPath

							if utils.IsUrl(result.Path) {
								if utils.IsSvgImportedFromJsx(result.Path, args) {
									result.Namespace = "svgFromJsx"
								} else {
									result.External = true
								}

								goto FINISH
							}

							// If the aliased path is a @rubygems path, resolve it the same way the
							// top-level `@rubygems/` handler does.
							//
							// `GemFromSpecifier` rather than `IsRubyGem` because it strips the
							// optional prefixes before testing the scope. `IsRubyGem` does not, so
							// an alias onto `unbundle:@rubygems/...` failed this guard, skipped gem
							// resolution entirely, and left the browser a bare specifier. The error
							// is discarded here on purpose - this only decides ownership of the
							// route, and `resolveRubygemPath` reports an unknown gem itself.
							if _, isGem, _ := utils.GemFromSpecifier(result.Path, cfg); isGem {
								if err := resolveRubygemPath(args, &result); err != nil {
									return result, err
								}

								goto FINISH
							}
						}
					}

					unbundled = resolveUnbundledPrefix(&result)
					if args.With["unbundle"] == "true" {
						unbundled = true
					}

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
						result.Path = filepath.Join(root, result.Path)
					}

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

						// If we have reached here, then the path is relative or a bare specifier.

						// Try to resolve the relative path manually without needing to call esbuild.Resolve, as
						// that can get expensive. Also, by not returning the path, we let esbuild handle
						// resolving the path, which is faster and also ensures tree shaking works.
						if utils.PathIsRelative(result.Path) && hasExt {
							if isCssImportedFromJs || result.Namespace == "svgFromJsx" || unbundled {
								result.Path = filepath.Join(args.ResolveDir, result.Path)
							} else {
								result.Path = ""
							}
						} else {
							resolveArgs := cloneResolveArgs(args)

							if utils.IsBareModule(result.Path) {
								// replace some npm modules with browser native APIs
								if replacement, ok := replacements.Get(result.Path, cfg); ok {
									result.Namespace = "replacement"
									result.PluginData = replacement
									goto FINISH
								}

								// If importer is a RubyGem...
								//
								// ...and that gem is NOT installed to node_modules, then change ResolveDir to the app
								// root. This ensures that bare imports are resolved relative to the app root, and not
								// the gem root, which allows us to use the app's package.json.
								//
								// ...OR that gem IS installed to node_modules, then change ResolveDir to the gem's
								// node_modules directory. This ensures that bare imports are resolved relative to the
								// gem's node_modules directory, and not the app's node_modules directory.
								gemName, _, foundGem := utils.PathIsRubyGem(args.Importer, cfg)
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
							}

							// Unqualified path! - use esbuild to resolve.
							ok := resolveWithEsbuild(resolveArgs, &result)
							if !ok {
								return result, nil
							}
						}
					}

				FINISH:

					if path.IsAbs(result.Path) {
						relPath := strings.TrimPrefix(result.Path, root)

						if aliasedPath, exists := utils.HasAlias(relPath, cfg); exists {
							if after, ok := strings.CutPrefix(aliasedPath, "unbundle:"); ok {
								aliasedPath = after
								unbundled = true
							}

							if utils.IsUrl(aliasedPath) {
								unbundled = false
								result.Path = aliasedPath
								result.External = true
							} else {
								result.Path = filepath.Join(root, aliasedPath)
							}

							debug.Debug(cfg.Debug, "OnResolve(.*):aliasAfter", relPath, result.Path)
						}
					}

					if unbundled {
						result.External = true
					}

					if result.External {
						// Returned path must be a URL path.
						if gemPath, ok := utils.RubyGemPathToUrlPath(result.Path, cfg); ok {
							result.Path = gemPath
						} else if rootPath, ok := rootPathToUrlPath(result.Path, cfg); ok {
							result.Path = rootPath
						}
					}

					debug.Debug(cfg.Debug, "OnResolve(.*):end", result)

					return result, nil
				})
		},
	}
}

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
