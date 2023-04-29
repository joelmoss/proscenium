package builder

import (
	"io"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/utils"
	"net/http"
	"net/url"
	"path"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

// Bundler plugin that bundles everything together.
//
//   - *.woff and *.woff2 files are externalized.
//   - URL's are encoded as a local URL path, and externalized.
var bundler = esbuild.Plugin{
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
				if args.PluginData != nil && args.PluginData.(PluginData).isResolvingPath {
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

				resolvedImport, matched := importmap.Resolve(args.Path, args.ResolveDir, root)
				if matched {
					result.Path = resolvedImport

					if path.IsAbs(result.Path) {
						return result, nil
					} else if utils.IsUrl(result.Path) {
						// result.Namespace = "url"
						result.Path = "/" + url.QueryEscape(result.Path)
						result.External = true
						return result, nil
					}
				}

				if isSvgImportedFromJsx(result.Path, args) {
					// We're importing an SVG file from JSX. Assigning the `svgFromJsx` namespace tells
					// the svg plugin to return the SVG as a JSX component.
					result.Namespace = "svgFromJsx"
				}

				// Mark as external if importing SVG from CSS.
				if strings.HasSuffix(args.Importer, ".css") && strings.HasSuffix(result.Path, ".svg") {
					ensureExternal()
				}

				// Absolute path - pass through as is.
				if path.IsAbs(args.Path) {
					if !result.External {
						result.Path = path.Join(root, args.Path)
					}

					return result, nil
				}

				// Resolve with esbuild
				r := build.Resolve(args.Path, esbuild.ResolveOptions{
					ResolveDir: args.ResolveDir,
					Importer:   args.Importer,
					Kind:       esbuild.ResolveJSImportStatement,
					PluginData: PluginData{isResolvingPath: true},
				})

				if len(r.Errors) > 0 {
					// Could not reolve the path, so pass through as external. This ensures we receive no
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

		build.OnLoad(esbuild.OnLoadOptions{Filter: ".*", Namespace: "url"},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				// pp.Println("[4] namespace(url)", args)

				res, err := http.Get(args.Path)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}
				defer res.Body.Close()
				bytes, err := io.ReadAll(res.Body)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				contents := string(bytes)

				loader := esbuild.LoaderJS
				if strings.HasSuffix(args.Path, ".css") {
					loader = esbuild.LoaderCSS
				}

				// Returning the resolveDir ensures that imports fall back to the context of the root
				// directory.
				return esbuild.OnLoadResult{
					Contents:   &contents,
					Loader:     loader,
					ResolveDir: root,
				}, nil
			})
	}}
