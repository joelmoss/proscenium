package resolver

import (
	"encoding/json"
	"errors"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"net/url"
	"path"
	"reflect"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type Options struct {
	// The path to build relative to `root`.
	Path string

	// The absolute file system path fof the importing file.
	Importer string

	// The working directory.
	Root string

	// Path to an import map (js or json), relative to the given root.
	ImportMapPath string

	// Import map as a string.
	ImportMap []byte
}

// Resolve the given `path` relative to the `root`, where the path is a URL path or bare specifier.
// This function is primarily intended to be used to resolve bare or NPM modules outside of any
// build.
//
// Returns an absolute URL path. That is, one that has a leading slash and can be appended to the
// app domain.
func Resolve(options Options) (string, error) {
	// Parse the import map - if any.
	err := importmap.Parse(options.ImportMap, options.ImportMapPath, options.Root)
	if err != nil {
		return "", errors.New("Failed to parse import map: " + err.Error())
	}

	// Look for a match in the import map
	resolvedImport, matched := importmap.Resolve(options.Path, options.Root, options.Root)
	if matched {
		if path.IsAbs(resolvedImport) {
			return strings.TrimPrefix(resolvedImport, options.Root), nil
		} else if utils.IsUrl(resolvedImport) {
			return "/" + url.QueryEscape(resolvedImport), nil
		}

		options.Path = resolvedImport
	}

	if utils.PathIsRelative(options.Path) {
		if options.Importer == "" {
			return "", errors.New("relative paths are not supported when an importer not is given")
		}

		return strings.TrimPrefix(path.Join(path.Dir(options.Importer), options.Path), options.Root), nil
	}

	// Absolute paths need no resolution.
	if path.IsAbs(options.Path) {
		return options.Path, nil
	}

	result := esbuild.Build(esbuild.BuildOptions{
		EntryPoints:   []string{options.Path},
		AbsWorkingDir: options.Root,
		Format:        esbuild.FormatESModule,
		Conditions:    []string{types.Env.String(), "proscenium"},
		Write:         false,
		Metafile:      true,

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},
	})

	if len(result.Errors) > 0 {
		return "", errors.New(result.Errors[0].Text)
	}

	var metadata struct{ Inputs map[string]interface{} }
	err = json.Unmarshal([]byte(result.Metafile), &metadata)
	if err != nil {
		return "", err
	}

	return "/" + reflect.ValueOf(metadata.Inputs).MapKeys()[0].String(), nil
}
