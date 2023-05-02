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

// Bundler plugin that bundles everything together.
//
//   - *.woff and *.woff2 files are externalized.
//   - URL's are encoded as a local URL path, and externalized.
var Bundler = esbuild.Plugin{
	Name: "bundler",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		// File types which should be external.
		build.OnResolve(esbuild.OnResolveOptions{Filter: `\.woff2?$`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				return esbuild.OnResolveResult{
					External: true,
				}, nil
			})

		build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?://`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// pp.Println("[1a] filter(^https://)", args)

				// URL's are external.
				return esbuild.OnResolveResult{
					Path:     "/" + url.QueryEscape(args.Path),
					External: true,
				}, nil
			})

		// Intercept import paths starting with "https%3A%2F%2F" and "http%3A%2F%2F", decode them back
		// to the original URL, and tag them with the url namespace.
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
					return esbuild.OnResolveResult{
						Namespace: "file",
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

				// pp.Println("[3] filter(.*)", args)

				// Pass through entry points.
				if args.Kind == esbuild.ResolveEntryPoint {
					return esbuild.OnResolveResult{}, nil
				}

				// Build the result.
				result := esbuild.OnResolveResult{Path: args.Path}

				// Used to ensure that the result is marked as external no matter what. If this is true, it
				// will override the result.External value.
				shouldBeExternal := false
				ensureExternal := func() {
					shouldBeExternal = true
					result.External = true
				}

				resolvedImport, importMapMatched := importmap.Resolve(args.Path, args.ResolveDir, root)
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

				if utils.IsCssImportedFromJs(result.Path, args) {
					// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
					// the css plugin to return the CSS as a JS object of class names (css module).
					result.PluginData = types.PluginData{ImportedFromJs: true}
				} else if utils.IsSvgImportedFromJsx(result.Path, args) {
					// We're importing an SVG file from JSX. Assigning the `svgFromJsx` namespace tells
					// the svg plugin to return the SVG as a JSX component.
					result.Namespace = "svgFromJsx"
				}

				// Mark as external if importing SVG from CSS.
				if strings.HasSuffix(args.Importer, ".css") && strings.HasSuffix(result.Path, ".svg") {
					ensureExternal()
				}

				// Absolute path - pass through as is.
				if path.IsAbs(result.Path) {
					if !shouldBeExternal {
						result.Path = path.Join(root, args.Path)
					}

					return result, nil
				}

				if !importMapMatched && !shouldBeExternal {
					// We got no match from the import map, and it should not be external, so we'll try to
					// resolve the path manually without needing to call esbuild.Resolve. By Not returning the
					// path, we let esbuild handle resolving the path, which also ensures tree shaking works.

					// If the path is relative, simply prepend the ResolveDir to it.
					if utils.PathIsRelative(result.Path) {
						result.Path = ""
						return result, nil
					}

					// If the path is a bare module, we'll pass through without returning a path.
					// FIXME: Because we return an empty path, subsequent onLoad callbacks will not receive
					// the PluginData. See https://github.com/evanw/esbuild/issues/3098
					if utils.IsBareModule(result.Path) {
						result.Path = ""
						return result, nil
					}
				}

				// Resolve with esbuild
				// TODO: try and avoid this call as much as possible!
				r := build.Resolve(args.Path, esbuild.ResolveOptions{
					ResolveDir: args.ResolveDir,
					Importer:   args.Importer,
					Kind:       esbuild.ResolveJSImportStatement,
					PluginData: types.PluginData{IsResolvingPath: true},
				})

				if len(r.Errors) > 0 {
					// Could not resolve the path, so pass through as external. This ensures we receive no
					// error, and instead allows the browser to handle the import failure.
					result.External = true
					return result, nil
				}

				if r.SideEffects {
					result.SideEffects = esbuild.SideEffectsTrue
				} else {
					result.SideEffects = esbuild.SideEffectsFalse
				}
				result.Path = r.Path
				result.External = r.External

				if shouldBeExternal {
					result.External = true
				}

				return result, nil
			})
	}}
