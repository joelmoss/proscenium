package plugin

import (
	"io"
	"net/http"
	"net/url"
	"os"

	"github.com/evanw/esbuild/pkg/api"
	httpcache "github.com/gregjones/httpcache/diskcache"
)

const shouldCache = true

var Url = api.Plugin{
	Name: "url",
	Setup: func(build api.PluginBuild) {
		// Intercept import paths starting with "http:" and "https:" so
		// esbuild doesn't attempt to map them to a file system location.
		// Tag them with the "url" namespace to associate them with
		// this plugin.
		build.OnResolve(api.OnResolveOptions{Filter: `^https?://`},
			func(args api.OnResolveArgs) (api.OnResolveResult, error) {
				return api.OnResolveResult{
					Path:      args.Path,
					Namespace: "url",
				}, nil
			})

		// We also want to intercept all import paths inside downloaded
		// files and resolve them against the original URL. All of these
		// files will be in the "url" namespace. Make sure to keep
		// the newly resolved URL in the "url" namespace so imports
		// inside it will also be resolved as URLs recursively.
		build.OnResolve(api.OnResolveOptions{Filter: ".*", Namespace: "url"},
			func(args api.OnResolveArgs) (api.OnResolveResult, error) {
				base, err := url.Parse(args.Importer)
				if err != nil {
					return api.OnResolveResult{}, err
				}

				relative, err := url.Parse(args.Path)
				if err != nil {
					return api.OnResolveResult{}, err
				}

				return api.OnResolveResult{
					Path:      base.ResolveReference(relative).String(),
					Namespace: "url",
				}, nil
			})

		// When a URL is loaded, we want to actually download the content from the internet.
		build.OnLoad(api.OnLoadOptions{Filter: ".*", Namespace: "url"},
			func(args api.OnLoadArgs) (api.OnLoadResult, error) {
				cache := httpcache.New(os.TempDir())
				if shouldCache {
					cached, ok := cache.Get(args.Path)
					if ok {
						contents := string(cached)
						return api.OnLoadResult{Contents: &contents}, nil
					}
				}

				result, err := http.Get(args.Path)
				if err != nil {
					return api.OnLoadResult{}, err
				}

				defer result.Body.Close()
				bytes, err := io.ReadAll(result.Body)
				if err != nil {
					return api.OnLoadResult{}, err
				}

				if shouldCache {
					cache.Set(args.Path, bytes)
				}

				contents := string(bytes)
				return api.OnLoadResult{Contents: &contents}, nil
			})
	},
}
