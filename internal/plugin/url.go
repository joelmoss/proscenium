package plugin

import (
	"errors"
	"fmt"
	"io"
	"joelmoss/proscenium/internal/utils"
	"net/http"
	"os"

	esbuild "github.com/evanw/esbuild/pkg/api"
	httpcache "github.com/gregjones/httpcache/diskcache"
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

var Url = esbuild.Plugin{
	Name: "url",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		// When a URL is loaded, we want to actually download the content from the internet. Note that
		// CSS is not parsed with our custom parser (ie. no CSS module or mixin support).
		build.OnLoad(esbuild.OnLoadOptions{Filter: ".*", Namespace: "url"},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				// pp.Println("[5] namespace(url)", args)

				if shouldCacheHttp {
					cached, ok := cache.Get(args.Path)
					if ok {
						contents := string(cached)

						loader := esbuild.LoaderJS
						if utils.PathIsCss(args.Path) {
							loader = esbuild.LoaderCSS
						}

						return esbuild.OnLoadResult{Contents: &contents, Loader: loader}, nil
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

				loader := esbuild.LoaderJS
				if utils.PathIsCss(args.Path) {
					loader = esbuild.LoaderCSS
				}

				return esbuild.OnLoadResult{Contents: &contents, Loader: loader, ResolveDir: root}, nil
			})
	},
}
