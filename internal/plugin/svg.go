package plugin

import (
	"errors"
	"fmt"
	"io"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"sync"

	httpcache "github.com/gregjones/httpcache/diskcache"
	"github.com/joelmoss/esbuild-internal/api"
	"github.com/peterbourgon/diskv"
)

// When importing an svg image from a jsx module, the svg is exported as a react component.
func Svg(cfg *types.ConfigT) api.Plugin {
	return api.Plugin{
		Name: "svg",
		Setup: func(build api.PluginBuild) {
			build.OnLoad(api.OnLoadOptions{Filter: `.*`, Namespace: "svgFromJsx"},
				func(args api.OnLoadArgs) (api.OnLoadResult, error) {
					contents, _, err := func() (string, string, error) {
						if utils.IsUrl(args.Path) {
							return DownloadURL(args.Path, true, cfg)
						}

						bytes, err := os.ReadFile(args.Path)
						if err != nil {
							return "", "", err
						}

						return string(bytes), "", nil
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
}

// Where a downloaded svg is cached, relative to the app root. Under the app's own tmp/, beside
// where the daemon materialises .rjs modules, rather than in the shared system temp dir. The old
// base path was os.TempDir() itself, which put cache entries loose among every other process'
// files - and made `EraseAll` walk the whole of it, which is not what anything wanted.
const svgCacheDir = "tmp/proscenium/svg-cache"

// Memoised per root rather than built per call: two diskv instances over one directory each keep
// their own mutex, so concurrent builds of the same app would not be serialised against each
// other. Keyed on the root because that is what decides the path, and one process can build
// several - the test suite does.
var (
	svgCachesMutex sync.Mutex
	svgCaches      = map[string]*svgCache{}
)

type svgCache struct {
	store *diskv.Diskv
	http  *httpcache.Cache
}

func svgCacheFor(cfg *types.ConfigT) *svgCache {
	svgCachesMutex.Lock()
	defer svgCachesMutex.Unlock()

	if cache, ok := svgCaches[cfg.RootPath]; ok {
		return cache
	}

	store := diskv.New(diskv.Options{
		BasePath:     filepath.Join(cfg.RootPath, svgCacheDir),
		CacheSizeMax: 1024 * 1024, // FIXME: This doesn't seem to have any effect
	})

	cache := &svgCache{store: store, http: httpcache.NewWithDiskv(store)}
	svgCaches[cfg.RootPath] = cache

	return cache
}

// Removes every cached response for this app, from disk and from diskv's own in-memory index.
// Worth asserting on, unlike the old whole-of-/tmp version: the directory belongs to Proscenium,
// so there is nothing in it that anybody else put there.
func EraseSvgCache(cfg *types.ConfigT) error {
	return svgCacheFor(cfg).store.EraseAll()
}

// The maximum size of an HTTP response body to cache.
var MaxHttpBodySize int64 = 1024 * 1024 * 1 // 1MB

func DownloadURL(url string, shouldCache bool, cfg *types.ConfigT) (string, string, error) {
	// Resolved once here rather than at each use, and only when it is going to be used at all: the
	// lookup makes the cache directory, and an app that never imports a remote svg has no reason
	// to grow one.
	var cache *httpcache.Cache
	if shouldCache {
		cache = svgCacheFor(cfg).http

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
