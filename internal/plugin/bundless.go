package plugin

import (
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/replacements"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"os"
	"path/filepath"
	"strings"

	"github.com/joelmoss/esbuild-internal/helpers"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

// Unbundles the path if it starts with "unbundle:". It resolves the path without the prefix, and to
// the virtual URL path. Meaning that an NPM package at "node_modules/foo/bar.js" will be reoslved
// to "/node_modules/foo/bar.js". If the package manager uses symlinks (eg. pnpm), then the path
// will be resolved to the symlinked path.
var Bundless = esbuild.Plugin{
	Name: "bundless",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		// Resolve with esbuild. Try and avoid this call as much as possible!
		resolveWithEsbuild := func(args esbuild.OnResolveArgs, onResolveResult *esbuild.OnResolveResult) bool {
			// If the path is a bare module, and the resolve dir is inside node_modules, then we need to
			// evaluate any symlinks and resolve the path to the real path. We want the real path to the
			// module when unbundling, otherwise dependencies of dependencies will not resolve correctly.
			if utils.IsBareModule(onResolveResult.Path) && helpers.IsInsideNodeModules(args.ResolveDir) {
				realResolveDir, err := filepath.EvalSymlinks(args.ResolveDir)
				if err != nil {
					debug.Debug("EvalSymlinks of ResolveDir failed!", err)
					return false
				}

				realImporter, err := filepath.EvalSymlinks(args.Importer)
				if err != nil {
					debug.Debug("EvalSymlinks of Importer failed!", err)
					return false
				}

				args.ResolveDir = realResolveDir
				args.Importer = realImporter
			}

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

				result := esbuild.OnResolveResult{
					Path:       args.Path,
					PluginData: types.PluginData{},
				}
				resolveUnbundledPrefix(&result)
				result.Path = strings.TrimPrefix(result.Path, "node_modules/")

				gemName, gemPath, err := utils.ResolveRubyGem(result.Path)
				if err != nil {
					return result, err
				} else {
					result.Namespace = "rubygems"

					if pluginData, ok := result.PluginData.(types.PluginData); ok {
						pluginData.GemPath = gemPath
						result.PluginData = pluginData
					}
				}

				if aliasedPath, exists := utils.HasAlias(result.Path); exists {
					result.Path = aliasedPath
					resolveUnbundledPrefix(&result)
				}

				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					if pluginData, ok := result.PluginData.(types.PluginData); ok {
						pluginData.ImportedFromJs = true
						result.PluginData = pluginData
					}
				}

				// If the path is an entrypoint, then it must be an absolute fileystem path.
				if args.Kind == esbuild.ResolveEntryPoint {
					realPath := filepath.Join(gemPath, utils.RemoveRubygemPrefix(result.Path, gemName))
					if pluginData, ok := result.PluginData.(types.PluginData); ok {
						pluginData.RealPath = realPath
						result.PluginData = pluginData
					}
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
						suffix := strings.TrimPrefix(filepath.ToSlash(result.Path), filepath.ToSlash(gemPath))
						result.Path = "/node_modules/" + types.RubyGemsScope + gemName + suffix
					}

					result.External = true
				}

				debug.Debug("OnResolve(@rubygems/*):end", result)

				return result, nil
			})

		// The path from a ruby gem will most likely not be the real FS path, so this will load their
		// contents while maintaining the virtual path (ie. @rubygems/foo).
		build.OnLoad(esbuild.OnLoadOptions{Namespace: "rubygems", Filter: ".*"},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				debug.Debug("OnLoad(rubygems):begin", args)

				realPath := args.PluginData.(types.PluginData).RealPath

				result := esbuild.OnLoadResult{
					Loader:     esbuild.LoaderDefault,
					ResolveDir: filepath.Dir(realPath),
					PluginData: types.PluginData{
						GemPath: args.PluginData.(types.PluginData).GemPath,
					},
				}

				if !utils.PathIsCss(realPath) {
					// Get file contents.
					contents, err := os.ReadFile(realPath)
					if err != nil {
						panic(err)
					}

					contentsAsString := string(contents)
					result.Contents = &contentsAsString
				}

				debug.Debug("OnLoad(rubygems):end", result)

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

				var isBare string
				var hasExt bool

				if utils.IsBareModule(result.Path) {
					if aliasedPath, exists := utils.HasAlias(result.Path); exists {
						result.Path = aliasedPath
						resolveUnbundledPrefix(&result)

						// If the aliased path is a @rubygems path, resolve it inline.
						if utils.IsRubyGem(result.Path) {
							result.Path = strings.TrimPrefix(result.Path, "node_modules/")

							// Verify the gem exists
							if _, _, err := utils.ResolveRubyGem(result.Path); err != nil {
								return result, err
							}

							result.External = true
							result.Path = "/node_modules/" + result.Path

							goto FINISH
						}
					}
				}

				isBare = utils.ExtractBareModule(result.Path)
				_, hasExt = utils.HasExtension(result.Path)

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

				if isBare != "" && hasExt {
					// Bare module with extension, so there is no need to resolve it if we prefix the path
					// with "/node_modules/".
					result.Path = "/node_modules/" + result.Path
					goto FINISH
				}

				if utils.PathIsAbsolute(result.Path) {
					if hasExt {
						// Absolute path and extension, so assume this is an app relative path, and return as is.
						goto FINISH
					} else {
						result.Path = filepath.Join(root, result.Path)
					}
				}

				// Try to resolve the relative path manually without needing to call esbuild.Resolve, as
				// that can get expensive.
				if utils.PathIsRelative(result.Path) && hasExt {
					result.Path = filepath.Join(args.ResolveDir, result.Path)
				} else {
					if isBare != "" {
						// replace some npm modules with browser native APIs
						if replacement, ok := replacements.Get(result.Path); ok {
							result.External = false
							result.Namespace = "replacement"
							result.PluginData = replacement
							goto FINISH
						}
					}

					// Unqualified path! - use esbuild to resolve.

					originalPath := result.Path
					resolveArgs := cloneResolveArgs(args)

					// Bare modules imported from a ruby gem are resolved as follows...
					// 1. use the unchanged ResolveDir, which will apply for NPM installed modules.
					// 2. use the gem path as the ResolveDir (if different), which will apply for non-NPM installed modules.
					// 3. try again using the root as the ResolveDir (if different), which will be the app.

					// 1
					ok := resolveWithEsbuild(resolveArgs, &result)
					if !ok {
						return result, nil
					}

					// 2
					if result.Path == "" && isBare != "" && args.Namespace == "rubygems" &&
						resolveArgs.ResolveDir != args.PluginData.(types.PluginData).GemPath {
						resolveArgs.ResolveDir = args.PluginData.(types.PluginData).GemPath
						result.Path = originalPath

						if ok := resolveWithEsbuild(resolveArgs, &result); !ok {
							return result, nil
						}
					}

					// 3
					if result.Path == "" && isBare != "" && args.Namespace == "rubygems" &&
						resolveArgs.ResolveDir != root {
						resolveArgs.ResolveDir = root
						result.Path = originalPath

						if ok := resolveWithEsbuild(resolveArgs, &result); !ok {
							return result, nil
						}
					}
				}

			FINISH:

				if result.Errors != nil {
					result.Warnings = result.Errors
					result.Errors = nil
					result.Path = args.Path
				}

				// Returned path must be a URL path.
				if gemPath, ok := utils.RubyGemPathToUrlPath(result.Path); ok {
					result.Path = gemPath
				} else if newPath, ok := rootPathToUrlPath(result.Path); ok {
					result.Path = newPath
				}

				if utils.PathIsAbsolute(result.Path) {
					if aliasedPath, exists := utils.HasAlias(result.Path); exists {
						result.Path, _ = strings.CutPrefix(aliasedPath, "unbundle:")
					}
				}

				debug.Debug("OnResolve:end", result)

				return result, nil
			})
	}}

// Converts an absolute file system path that begins with the root, to a URL path.
func rootPathToUrlPath(fsPath string) (urlPath string, found bool) {
	if after, ok := strings.CutPrefix(filepath.ToSlash(fsPath), filepath.ToSlash(types.Config.RootPath)); ok {
		return after, true
	}

	return "", false
}
