package replacements

// Borrowed from the amazing esm.sh!

import (
	"embed"
	"errors"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"strings"
	"sync"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

//go:embed src
var efs embed.FS

var npmReplacements = map[string][]byte{}
var buildOnce sync.Once
var buildErr error

func Get(specifier string, cfg *types.ConfigT) ([]byte, bool) {
	var replacement []byte
	var ok bool

	if cfg.Environment == types.DevEnv {
		replacement, ok = get(specifier + "_browser_dev")
		if !ok {
			replacement, ok = get(specifier + "_dev")
		}
	}
	if !ok {
		replacement, ok = get(specifier + "_browser")
	}
	if !ok {
		replacement, ok = get(specifier)
	}

	return replacement, ok
}

// Get returns the npm replacement by the given name.
func get(name string) ([]byte, bool) {
	ret, ok := npmReplacements[name]
	return ret, ok
}

// Build builds the npm replacements. Safe to call concurrently - the embedded source files are
// only ever walked and transformed once, via sync.Once.
//
// Built into a local table and published only once complete: a panic part-way through would
// otherwise leave Once done, buildErr nil and a partial table published, and every later call
// would report success against it. The callers recover panics now, so this one has to as well.
func Build() (n int, err error) {
	buildOnce.Do(func() {
		built := map[string][]byte{}

		if perr := utils.Recover(func() {
			buildErr = walkEmbedFS("src", func(path string) error {
				sourceCode, err := efs.ReadFile(path)
				if err != nil {
					return err
				}
				ret := esbuild.Transform(string(sourceCode), esbuild.TransformOptions{
					Target:            esbuild.ES2022,
					Format:            esbuild.FormatESModule,
					Platform:          esbuild.PlatformBrowser,
					MinifyWhitespace:  true,
					MinifyIdentifiers: true,
					MinifySyntax:      true,
					Loader:            esbuild.LoaderJS,
				})
				if len(ret.Errors) > 0 {
					return errors.New(ret.Errors[0].Text)
				}
				specifier := strings.TrimSuffix(strings.TrimSuffix(strings.TrimPrefix(path, "src/"), ".mjs"), "/index")
				built[specifier] = ret.Code
				return nil
			})
		}); perr != nil {
			buildErr = perr
		}

		if buildErr == nil {
			npmReplacements = built
		}
	})

	return len(npmReplacements), buildErr
}

func walkEmbedFS(dir string, fn func(path string) error) error {
	entries, err := efs.ReadDir(dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		path := dir + "/" + entry.Name()
		if entry.IsDir() {
			if err := walkEmbedFS(path, fn); err != nil {
				return err
			}
		} else if strings.HasSuffix(path, ".mjs") {
			if err := fn(path); err != nil {
				return err
			}
		}
	}
	return nil
}
