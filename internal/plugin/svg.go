package plugin

import (
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
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

					contents, err = svgToJsx(contents)
					if err != nil {
						return api.OnLoadResult{}, fmt.Errorf("cannot read %v as SVG: %w", args.Path, err)
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
						ResolveDir: filepath.ToSlash(filepath.Dir(args.Path)),
						Loader:     loader,
					}, nil
				})
		},
	}
}

// Names an SVG may use, which are interpolated into JSX unquoted, so they are all that stands
// between the markup and code. An element name must also be one JSX reads as a string, as it does a
// lowercase name or one holding a `-` or `:`. Any other is a reference to a variable in scope.
var svgName = regexp.MustCompile(`^[A-Za-z_][\w-]*(:[A-Za-z_][\w-]*)?$`)

func isSvgTagName(name string) bool {
	return svgName.MatchString(name) && (name[0] >= 'a' && name[0] <= 'z' || strings.ContainsAny(name, "-:"))
}

// Converts SVG markup to JSX in which every attribute value and every piece of text is a JSON
// string literal, so nothing in the SVG is evaluated. It used to be spliced into the module as JSX
// source, which made a remote SVG code: `{proscenium.env.API_KEY}` in one was replaced with the
// key's value, and anything after the closing tag ran in the bundle. Only the root element is
// read; anything after it is ignored.
func svgToJsx(svg string) (string, error) {
	decoder := xml.NewDecoder(strings.NewReader(svg))
	// Lenient, so real-world SVGs that are not strict XML still load: HTML entities such as &nbsp;,
	// and a bare &.
	decoder.Strict = false
	decoder.Entity = xml.HTMLEntity

	var out, text strings.Builder
	var open []string

	// Text arrives in pieces (a CDATA section is its own token), and is written as one child, as
	// JSX would have.
	flushText := func() {
		if t := jsxText(text.String()); t != "" {
			fmt.Fprintf(&out, "{%s}", utils.JsString(t))
		}
		text.Reset()
	}

	for {
		// RawToken rather than Token: Token replaces a prefix such as `xlink:` with its namespace
		// URL. RawToken does not check that end tags match, so the open stack does.
		token, err := decoder.RawToken()
		if err == io.EOF && len(open) > 0 {
			return "", fmt.Errorf("unclosed element %q", open[len(open)-1])
		}
		if err == io.EOF {
			return "", errors.New("no root element")
		}
		if err != nil {
			return "", err
		}

		switch t := token.(type) {
		case xml.StartElement:
			name := xmlName(t.Name)
			if !isSvgTagName(name) {
				return "", fmt.Errorf("invalid element name %q", name)
			}

			flushText()
			fmt.Fprintf(&out, "<%s", name)
			for _, attr := range t.Attr {
				attrName := xmlName(attr.Name)
				if !svgName.MatchString(attrName) {
					return "", fmt.Errorf("invalid attribute name %q", attrName)
				}

				fmt.Fprintf(&out, " %s={%s}", attrName, utils.JsString(attr.Value))
			}
			out.WriteString(">")

			open = append(open, name)

		case xml.EndElement:
			name := xmlName(t.Name)
			if len(open) == 0 || open[len(open)-1] != name {
				return "", fmt.Errorf("unexpected closing tag %q", name)
			}

			flushText()
			fmt.Fprintf(&out, "</%s>", name)

			open = open[:len(open)-1]
			if len(open) == 0 {
				return out.String(), nil
			}

		case xml.CharData:
			// Text before the root is not part of the SVG.
			if len(open) > 0 {
				text.Write(t)
			}
		}
	}
}

var jsxLineBreak = regexp.MustCompile("\r\n|[\r\n\u2028\u2029]")

// JSX's rule for text between tags, which SVG text followed while it was spliced in as JSX: a line
// break and the spaces and tabs around it become one space, and text that is only that is dropped.
// So the indentation of a pretty-printed SVG adds no children, which would make Children.only
// throw, while a space between two elements on one line is kept.
//
// ponytail: encoding/xml decodes entities before this sees the text, so an entity that is
// whitespace (`&#10;`) is treated as formatting, where JSX kept it. Only spaces and tabs are
// trimmed, so `&nbsp;` survives at the edge of a line. Decode entities here if that ever matters.
func jsxText(text string) string {
	lines := jsxLineBreak.Split(text, -1)
	kept := lines[:0]

	for i, line := range lines {
		if i > 0 {
			line = strings.TrimLeft(line, " \t")
		}
		if i < len(lines)-1 {
			line = strings.TrimRight(line, " \t")
		}
		if line != "" {
			kept = append(kept, line)
		}
	}

	return strings.Join(kept, " ")
}

func xmlName(name xml.Name) string {
	if name.Space == "" {
		return name.Local
	}

	return name.Space + ":" + name.Local
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
		BasePath:     utils.JoinFsPath(cfg.RootPath, svgCacheDir),
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
