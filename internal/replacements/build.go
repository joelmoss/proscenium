package replacements

// Borrowed from the amazing esm.sh!

import (
	"embed"
	"errors"
	"joelmoss/proscenium/internal/types"
	"strings"

	esbuild "github.com/ije/esbuild-internal/api"
)

//go:embed src
var efs embed.FS

var npmReplacements = map[string][]byte{}

func Get(specifier string) ([]byte, bool) {
	var replacement []byte
	var ok bool

	if types.Config.Environment == types.DevEnv {
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

// Build builds the npm replacements.
func Build() (n int, err error) {
	if len(npmReplacements) > 0 {
		return len(npmReplacements), nil
	}

	err = walkEmbedFS("src", func(path string) error {
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
		npmReplacements[specifier] = ret.Code
		return nil
	})
	if err != nil {
		return
	}

	return len(npmReplacements), nil
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
