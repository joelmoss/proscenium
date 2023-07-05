package plugin

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"net/url"
	"path"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type esbuildResolveResult struct {
	Path        string
	SideEffects esbuild.SideEffects
	External    bool
}

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

			return result, true
		}

		// File types which should be external.
		build.OnResolve(esbuild.OnResolveOptions{Filter: `\.(gif|jpe?g|png|woff2?)$`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				return esbuild.OnResolveResult{
					External: true,
				}, nil
			})

		// Encode URL's and return with a prefixed slash. Then externalise them. This allows us to treat
		// URL's as local paths for later bundling and transforming.
		build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?://`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// pp.Println("[1a] filter(^https://)", args)

				// SVG files imported from JSX should be downloaded and bundled as JSX with the svgFromJsx
				// namespace.
				if utils.IsSvgImportedFromJsx(args.Path, args) {
					return esbuild.OnResolveResult{
						Path:      args.Path,
						Namespace: "svgFromJsx",
					}, nil
				}

				// URL's are external.
				return esbuild.OnResolveResult{
					Path:     "/" + url.QueryEscape(args.Path),
					External: true,
				}, nil
			})

		// Intercept URL encoded paths starting with "https%3A%2F%2F" and "http%3A%2F%2F", decode them
		// back to the original URL, and tag them with the url namespace.
		build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?%3A%2F%2F`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// pp.Println("[1b] filter(^https?%3A%2F%2F)", args)

				path, err := url.QueryUnescape(args.Path)
				if err != nil {
					return esbuild.OnResolveResult{}, err
				}

				return esbuild.OnResolveResult{
					Path:      path,
					Namespace: "url",
				}, nil
			})

		// Handles dependencies of URL modules. Relative and absolute paths are resolved relative to the
		// URL. While bare paths are resolved relative to the local root.
		build.OnResolve(esbuild.OnResolveOptions{Filter: ".*", Namespace: "url"},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// pp.Println("[2] namespace(url)", args)

				if utils.IsBareModule(args.Path) {
					// pp.Println("[2a] namespace(url)", args)
					return esbuild.OnResolveResult{
						// Namespace: "file",
					}, nil
				}

				base, err := url.Parse(args.Importer)
				if err != nil {
					return esbuild.OnResolveResult{}, err
				}

				relative, err := url.Parse(args.Path)
				if err != nil {
					return esbuild.OnResolveResult{}, err
				}

				return esbuild.OnResolveResult{
					Path:      base.ResolveReference(relative).String(),
					Namespace: "url",
				}, nil
			})

		build.OnResolve(esbuild.OnResolveOptions{Filter: ".*"},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// Pass through paths that are currently resolving.
				if args.PluginData != nil && args.PluginData.(types.PluginData).IsResolvingPath {
					return esbuild.OnResolveResult{}, nil
				}

				// Pass through entry points.
				if args.Kind == esbuild.ResolveEntryPoint {
					return esbuild.OnResolveResult{}, nil
				}

				// pp.Println("[3] filter(.*)", args)

				// Build the result.
				result := esbuild.OnResolveResult{Path: args.Path}

				// Used to ensure that the result is marked as external no matter what. If this is true, it
				// will override the result.External value.
				shouldBeExternal := false
				ensureExternal := func() {
					shouldBeExternal = true
					result.External = true
				}

				resolvedImport, importMapMatched := importmap.Resolve(args.Path, args.ResolveDir)
				if importMapMatched {
					result.Path = resolvedImport

					if path.IsAbs(result.Path) {
						return result, nil
					} else if utils.IsUrl(result.Path) {
						result.Path = "/" + url.QueryEscape(result.Path)
						result.External = true
						return result, nil
					}
				}

				isCssImportedFromJs := false
				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					isCssImportedFromJs = true
					result.PluginData = types.PluginData{ImportedFromJs: true}
				} else if utils.IsCssModuleImportedFromCssModule(result.Path, args) {
					pd := types.PluginData{CssModuleImportedFromCssModule: true}
					if args.PluginData != nil {
						pd.CssModuleHash = args.PluginData.(types.PluginData).CssModuleHash
					}

					result.PluginData = pd
					result.Namespace = "cssModuleFromCssmodule"
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
				if path.IsAbs(result.Path) && !shouldBeExternal {
					result.Path = path.Join(root, args.Path)
				}

				// If we have reached here, then the path is relative or a bare specifier.

				if shouldBeExternal {
					// It's external, so pass it through for esbuild to resolve.
					result.External = true
				} else {
					// If the path should not be external, then we may still need to resolve it, as it may not
					// be a fully qualified path.

					// Try to resolve the relative path manually without needing to call esbuild.Resolve, as
					// that can get expensive. Also, by not returning the path, we let esbuild handle
					// resolving the path, which is faster and also ensures tree shaking works.
					if utils.PathIsRelative(result.Path) {
						if isCssImportedFromJs || result.Namespace == "svgFromJsx" || result.Namespace == "cssModuleFromCssmodule" {
							result.Path = path.Join(args.ResolveDir, result.Path)
						} else {
							result.Path = ""
						}
					} else {
						// If we have reached this far, then path is a bare specifier. Use esbuild to resolve.
						resolveResult, ok := resolveWithEsbuild(result.Path, args)

						result.Path = resolveResult.Path
						result.External = resolveResult.External
						result.SideEffects = resolveResult.SideEffects

						if !ok {
							return result, nil
						}
					}
				}

				return result, nil
			})
	}}
