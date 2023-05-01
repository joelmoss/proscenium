package plugin

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"net/url"
	"path"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

var Unbundler = esbuild.Plugin{
	Name: "unbundler",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		// Intercept import paths starting with "http:" and "https:" so esbuild doesn't attempt to map
		// them to a file system location. The resulting path is URL encoded, then when the import is
		// later resolved, it is caught in a later OnResolve callback, decoded back to the original
		// URL, bundled, and tagged with the url namespace.
		build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?://`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// pp.Println("[1] filter(^https://)", args)

				return esbuild.OnResolveResult{
					Path:     "/" + url.QueryEscape(args.Path),
					External: true,
				}, nil
			})

		// Intercept import paths starting with "https%3A%2F%2F" and "http%3A%2F%2F", decode them back
		// to the original URL, and tag them with the url namespace.
		build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?%3A%2F%2F`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// pp.Println("[2] filter(^https?%3A%2F%2F)", args)

				path, err := url.QueryUnescape(args.Path)
				if err != nil {
					return esbuild.OnResolveResult{}, err
				}

				return esbuild.OnResolveResult{
					Path:      path,
					Namespace: "url",
				}, nil
			})

		// Intercept all import paths inside imported files tagged with the url namespace and
		// resolve them against the original URL. All of these import paths will be URL encoded and
		// marked as external. This ensures imports inside an imported URL will also be resolved as
		// URLs recursively.
		build.OnResolve(esbuild.OnResolveOptions{Filter: ".*", Namespace: "url"},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// pp.Println("[3] namespace(url)", args)

				// Pass through bare imports.
				if utils.IsBareModule(args.Path) {
					return esbuild.OnResolveResult{}, nil
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
					Path:     "/" + url.QueryEscape(base.ResolveReference(relative).String()),
					External: true,
				}, nil
			})

		build.OnResolve(esbuild.OnResolveOptions{Filter: `.*`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// Pass through paths that are currently resolving.
				if args.PluginData != nil && args.PluginData.(types.PluginData).IsResolvingPath {
					return esbuild.OnResolveResult{}, nil
				}

				// pp.Println("[4] filter(.*)", args)

				// Pass through entry points.
				if args.Kind == esbuild.ResolveEntryPoint {
					return esbuild.OnResolveResult{}, nil
				}

				result := esbuild.OnResolveResult{Path: args.Path, External: true}

				resolvedImport, matched := importmap.Resolve(args.Path, args.ResolveDir, root)
				if matched {
					if path.IsAbs(resolvedImport) {
						return esbuild.OnResolveResult{
							// Make sure the path is relative to the root.
							Path:     strings.TrimPrefix(resolvedImport, root),
							External: true,
						}, nil
					} else if utils.IsUrl(resolvedImport) {
						return esbuild.OnResolveResult{
							Path:     "/" + url.QueryEscape(resolvedImport),
							External: true,
						}, nil
					}

					result.Path = resolvedImport
				}

				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					result.PluginData = types.PluginData{ImportedFromJs: true}
					result.External = false
				} else if utils.IsSvgImportedFromJsx(result.Path, args) {
					// We're importing an SVG file from JSX. Assigning the `svgFromJsx` namespace tells
					// the svg plugin to return the SVG as a JSX component.
					result.Namespace = "svgFromJsx"
					result.External = false
				}

				resolveDir := args.ResolveDir

				// Absolute path - pass through as is.
				if path.IsAbs(result.Path) {
					if !result.External {
						result.Path = path.Join(root, result.Path)
					}

					return result, nil
				}

				if resolveDir == "" {
					resolveDir = root
				}

				// Resolve with esbuild
				r := build.Resolve(result.Path, esbuild.ResolveOptions{
					ResolveDir: resolveDir,
					Importer:   args.Importer,
					Kind:       args.Kind,
					PluginData: types.PluginData{IsResolvingPath: true},
				})
				if len(r.Errors) > 0 {
					result.Errors = r.Errors
					return result, nil
				}

				if r.SideEffects {
					result.SideEffects = esbuild.SideEffectsTrue
				} else {
					result.SideEffects = esbuild.SideEffectsFalse
				}
				result.Path = r.Path

				// Make sure the path is relative to the root.
				if result.External {
					result.Path = strings.TrimPrefix(result.Path, root)
				}

				return result, nil
			})
	},
}
