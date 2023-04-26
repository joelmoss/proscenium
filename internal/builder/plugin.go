package builder

import (
	"errors"
	"fmt"
	"io"
	"joelmoss/proscenium/internal/css"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"net/http"
	"net/url"
	"os"
	"path"
	"regexp"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
	httpcache "github.com/gregjones/httpcache/diskcache"
	"github.com/k0kubun/pp/v3"
	"github.com/peterbourgon/diskv"
)

const shouldCacheHttp = true

// The maximum size of an HTTP response body to cache.
var MaxHttpBodySize int64 = 1024 * 1024 * 1 // 1MB

var DiskvCache = diskv.New(diskv.Options{
	BasePath:     os.TempDir(),
	CacheSizeMax: 1024 * 1024, // FIXME: This doesn't seem to have any effect
})
var cache = httpcache.NewWithDiskv(DiskvCache)

type PluginData = struct {
	isResolvingPath bool
	importedFromJs  bool
}

func mainPlugin(options types.PluginOptions) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "buildPlugin",
		Setup: func(build esbuild.PluginBuild) {
			root := build.InitialOptions.AbsWorkingDir

			// Intercept import paths starting with "http:" and "https:" so esbuild doesn't attempt to map
			// them to a file system location. The resulting path is URL encoded, then when the import is
			// later resolved, it is caught in a later OnResolve callback, decoded back to the original
			// URL, bundled, and tagged with the url namespace.
			build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?://`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					pp.Println("1", args)

					return esbuild.OnResolveResult{
						Path:     "/" + url.QueryEscape(args.Path),
						External: true,
					}, nil
				})

			// Intercept import paths starting with "https%3A%2F%2F" and "http%3A%2F%2F", decode them back
			// to the original URL, and tag them with the url namespace.
			build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?%3A%2F%2F`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					pp.Println("2", args)

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
					pp.Println("3", args)

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
					// Pass through entry points.
					if args.Kind == esbuild.ResolveEntryPoint {
						return esbuild.OnResolveResult{}, nil
					}

					// Pass through paths that are currently resolving.
					if args.PluginData != nil && args.PluginData.(PluginData).isResolvingPath {
						return esbuild.OnResolveResult{}, nil
					}

					pp.Println("4", args)

					if options.ImportMap != nil {
						resolvedImport, matched := importmap.Resolve(args.Path, args.ResolveDir, options.ImportMap)
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

							args.Path = resolvedImport
						}
					}

					result := esbuild.OnResolveResult{External: true}

					if isCssImportedFromJs(args) {
						// We're importing a CSS file from JS(X). Assigning `pluginData.importedFromJs` tells
						// the css plugin to return the CSS as a JS object of class names (css module).
						result.PluginData = PluginData{importedFromJs: true}
						result.External = false
					}

					resolveDir := args.ResolveDir

					// Absolute path - pass through as is.
					if path.IsAbs(args.Path) {
						if result.External {
							return result, nil
						} else {
							result.Path = path.Join(root, args.Path)
							return result, nil
						}
					}

					if resolveDir == "" {
						resolveDir = root
					}

					// Resolve with esbuild
					r := build.Resolve(args.Path, esbuild.ResolveOptions{
						ResolveDir: resolveDir,
						Importer:   args.Importer,
						Kind:       args.Kind,
						PluginData: PluginData{isResolvingPath: true},
					})
					if len(r.Errors) > 0 {
						result.Errors = r.Errors
						return result, nil
					}

					if args.Kind == esbuild.ResolveJSImportStatement &&
						strings.HasSuffix(r.Path, ".svg") &&
						strings.HasSuffix(args.Importer, ".jsx") {
						result.Namespace = "svgFromJsx"
						result.External = false
					}

					// Make sure the path is relative to the root.
					if result.External {
						result.Path = strings.TrimPrefix(r.Path, root)
					} else {
						result.Path = r.Path
					}

					return result, nil
				})

			// When a URL is loaded, we want to actually download the content from the internet.
			build.OnLoad(esbuild.OnLoadOptions{Filter: ".*", Namespace: "url"},
				func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
					if shouldCacheHttp {
						cached, ok := cache.Get(args.Path)
						if ok {
							contents := string(cached)

							if pathIsCss(args.Path) {
								contents, err := css.ParseCss(contents, args.Path, root)
								if err != nil {
									return esbuild.OnLoadResult{}, err
								}

								return esbuild.OnLoadResult{Contents: &contents, Loader: esbuild.LoaderCSS}, nil
							}

							return esbuild.OnLoadResult{Contents: &contents}, nil
						}
					}

					result, err := http.Get(args.Path)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					defer result.Body.Close()

					r := http.MaxBytesReader(nil, result.Body, MaxHttpBodySize)

					if result.StatusCode > 299 {
						err := fmt.Sprintf("Fetch of %v failed with status code: %d", args.Path, result.StatusCode)
						return esbuild.OnLoadResult{}, errors.New(err)
					}

					bytes, err := io.ReadAll(r)
					if err != nil {
						errMsg := fmt.Sprintf("Fetch of %v failed: %v", args.Path, err.Error())
						return esbuild.OnLoadResult{}, errors.New(errMsg)
					}

					if shouldCacheHttp {
						cache.Set(args.Path, bytes)
					}

					contents := string(bytes)

					if pathIsCss(args.Path) {
						contents, err := css.ParseCss(contents, args.Path, root)
						if err != nil {
							return esbuild.OnLoadResult{}, err
						}

						return esbuild.OnLoadResult{Contents: &contents, Loader: esbuild.LoaderCSS}, nil
					}

					return esbuild.OnLoadResult{Contents: &contents}, nil
				})

			// Parse CSS files.
			build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
				func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {

					// relativePath := strings.TrimPrefix(args.Path, root)
					hash := utils.ToDigest(args.Path)
					pp.Println(`\.css$`, args, hash)

					importedFromJs := args.PluginData != nil && args.PluginData.(PluginData).importedFromJs

					// If path is a CSS module, imported from JS, and a side-loaded ViewComponent stylesheet,
					// simply return a JS proxy of the class names. The stylesheet itself will have already been
					// side loaded. This avoids compiling the CSS all over again.
					// if pathIsCssModule(args.Path) && importedFromJs {
					// 	contents := cssModulesProxyTemplate(hash)
					// 	return esbuild.OnLoadResult{
					// 		Contents:   &contents,
					// 		ResolveDir: root,
					// 		Loader:     esbuild.LoaderJS,
					// 	}, nil
					// }

					// If stylesheet is imported from JS, then we return JS code that appends the stylesheet
					// in a <style> tag in the <head> of the page, and if the stylesheet is a CSS module, it
					// exports a plain object of class names.
					if importedFromJs {
						// debugComment := ""
						// if options.Env != types.ProdEnv {
						// 	debugComment = `e.before(document.createComment('` + args.Path + `'));`
						// }

						// contents = `
						// 	let e = document.querySelector('#_` + hash + `');
						// 	if (!e) {
						// 		e = document.createElement('style');
						// 		e.id = '_` + hash + `';
						// 		document.head.appendChild(e);
						// 		` + debugComment + `
						// 		e.appendChild(document.createTextNode(` + "`" + contents + "`" + `));
						// 	}
						// `

						contents := `
							let e = document.querySelector('#_` + hash + `');
							if (!e) {
								e = document.createElement('link');
								e.id = '_` + hash + `';
								e.rel = 'stylesheet';
								e.href = '` + strings.TrimPrefix(args.Path, root) + `';
								document.head.appendChild(e);
							}
						`

						if pathIsCssModule(args.Path) {
							contents = contents + cssModulesProxyTemplate(hash)
						}

						return esbuild.OnLoadResult{
							Contents:   &contents,
							ResolveDir: root,
							Loader:     esbuild.LoaderJS,
						}, nil
					}

					contents, err := css.ParseCssFile(args.Path, root)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					return esbuild.OnLoadResult{
						Contents: &contents,
						Loader:   esbuild.LoaderCSS,
					}, nil
				})
		},
	}
}

func pathIsCss(path string) bool {
	var re = regexp.MustCompile(`\.css$`)
	return re.MatchString(path)
}

func pathIsCssModule(path string) bool {
	var re = regexp.MustCompile(`\.module\.css$`)
	return re.MatchString(path)
}

func pathIsJs(path string) bool {
	var re = regexp.MustCompile(`\.jsx?$`)
	return re.MatchString(path)
}

func isCssImportedFromJs(args esbuild.OnResolveArgs) bool {
	return args.Kind == esbuild.ResolveJSImportStatement &&
		pathIsCss(args.Path) &&
		pathIsJs(args.Importer)
}

func cssModulesProxyTemplate(hash string) string {
	return `
    export default new Proxy( {}, {
      get(target, prop, receiver) {
        if (prop in target || typeof prop === 'symbol') {
          return Reflect.get(target, prop, receiver);
        } else {
          return prop + '` + hash + `';
        }
      }
    });
	`
}
