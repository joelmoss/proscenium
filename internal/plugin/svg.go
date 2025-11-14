package plugin

import (
	"errors"
	"fmt"
	"io"
	"joelmoss/proscenium/internal/utils"
	"mime"
	"net/http"
	"os"
	"path/filepath"

	httpcache "github.com/gregjones/httpcache/diskcache"
	"github.com/ije/esbuild-internal/api"
	"github.com/peterbourgon/diskv"
)

// When importing an svg image from a jsx module, the svg is exported as a react component.
var Svg = api.Plugin{
	Name: "svg",
	Setup: func(build api.PluginBuild) {
		build.OnLoad(api.OnLoadOptions{Filter: `.*`, Namespace: "svgFromJsx"},
			func(args api.OnLoadArgs) (api.OnLoadResult, error) {
				contents, _, err := func() (string, string, error) {
					if utils.IsUrl(args.Path) {
						return DownloadURL(args.Path, true)
					} else {
						bytes, err := os.ReadFile(args.Path)
						if err != nil {
							return "", "", err
						}

						return string(bytes), "", nil
					}
				}()

				if err != nil {
					return api.OnLoadResult{}, err
				}

				contents = fmt.Sprintf(`
					import { cloneElement, Children } from 'react';
					const svg = %s;
					const props = { ...svg.props, className: svg.props.class };
					delete props.class;
					export default function() {
						return <svg { ...props }>{Children.only(svg.props.children)}</svg>
					}
				`, contents)

				loader := api.LoaderJSX
				if utils.PathIsTsx(args.Path) {
					loader = api.LoaderTSX
				}

				return api.OnLoadResult{
					Contents:   &contents,
					ResolveDir: filepath.Dir(args.Path),
					Loader:     loader,
				}, nil
			})
	},
}

// The maximum size of an HTTP response body to cache.
var MaxHttpBodySize int64 = 1024 * 1024 * 1 // 1MB

var DiskvCache = diskv.New(diskv.Options{
	BasePath:     os.TempDir(),
	CacheSizeMax: 1024 * 1024, // FIXME: This doesn't seem to have any effect
})
var cache = httpcache.NewWithDiskv(DiskvCache)

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
