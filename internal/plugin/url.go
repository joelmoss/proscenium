package plugin

import (
	"errors"
	"fmt"
	"io"
	"joelmoss/proscenium/internal/utils"
	"mime"
	"net/http"
	"os"

	esbuild "github.com/evanw/esbuild/pkg/api"
	httpcache "github.com/gregjones/httpcache/diskcache"
	"github.com/peterbourgon/diskv"
)

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

		// When a URL is loaded, we want to actually download the content from the internet.
		// Note that CSS is not parsed with our custom parser (ie. no CSS module, mixin support).
		build.OnLoad(esbuild.OnLoadOptions{Filter: ".*", Namespace: "url"},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				// pp.Println("[5] namespace(url)", args)

				contents, contentType, err := DownloadURL(args.Path, true)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				loader := esbuild.LoaderJS
				if utils.PathIsCss(args.Path) || contentType == "text/css" {
					loader = esbuild.LoaderCSS
				} else if utils.PathIsSvg(args.Path) {
					loader = esbuild.LoaderText
				}

				return esbuild.OnLoadResult{
					Contents:   &contents,
					Loader:     loader,
					ResolveDir: root,
				}, nil
			})
	},
}

func DownloadURL(url string, shouldCache bool) (string, string, error) {
	if shouldCache {
		cachedContent, ok := cache.Get(url)
		if ok {
			cachedMediaType, ok := cache.Get(fmt.Sprint("contentType|", url))
			if ok {
				return string(cachedContent), string(cachedMediaType), nil
			} else {
				return string(cachedContent), "", nil
			}
		}
	}

	result, err := http.Get(url)
	if err != nil {
		errMsg := fmt.Sprintf("Fetch of %v failed: %v", url, err.Error())
		return "", "", errors.New(errMsg)
	}

	defer result.Body.Close()

	r := http.MaxBytesReader(nil, result.Body, MaxHttpBodySize)

	if result.StatusCode > 299 {
		err := fmt.Sprintf("Fetch of %v failed with status code: %d", url, result.StatusCode)
		return "", "", errors.New(err)
	}

	bytes, err := io.ReadAll(r)
	if err != nil {
		errMsg := fmt.Sprintf("Fetch of %v failed: %v", url, err.Error())
		return "", "", errors.New(errMsg)
	}

	contentType := result.Header.Get("Content-Type")
	mediaType, _, err := mime.ParseMediaType(contentType)
	if err == nil && shouldCache {
		cache.Set(fmt.Sprint("contentType|", url), []byte(mediaType))
	}

	if shouldCache {
		cache.Set(url, bytes)
	}

	return string(bytes), mediaType, nil
}
