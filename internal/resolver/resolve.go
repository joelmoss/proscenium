package resolver

import (
	"encoding/json"
	"errors"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"net/url"
	"os"
	"path"
	"reflect"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type Options struct {
	// The path to build relative to `root`.
	Path string

	// The working directory.
	Root string

	// The environment (1 = development, 2 = test, 3 = production)
	Env types.Environment

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
	os.Setenv("RAILS_ENV", options.Env.String())

	// Parse the import map - if any.
	imap, err := importmap.Parse(options.ImportMap, options.ImportMapPath, options.Root, options.Env)
	if err != nil {
		return "", errors.New("Failed to parse import map: " + err.Error())
	}

	if imap != nil {
		// Look for a match in the import map
		resolvedImport, matched := importmap.Resolve(options.Path, options.Root, imap)
		if matched {
			if path.IsAbs(resolvedImport) {
				return strings.TrimPrefix(resolvedImport, options.Root), nil
			} else if utils.IsUrl(resolvedImport) {
				return "/" + url.QueryEscape(resolvedImport), nil
			}

			options.Path = resolvedImport
		}
	}

	// Absolute paths need no resolution.
	if path.IsAbs(options.Path) {
		return options.Path, nil
	}

	result := esbuild.Build(esbuild.BuildOptions{
		EntryPoints:   []string{options.Path},
		AbsWorkingDir: options.Root,
		Format:        esbuild.FormatESModule,
		Conditions:    []string{options.Env.String()},
		Write:         false,
		Metafile:      true,
		MainFields:    []string{"module", "browser", "main"},
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

// Resolves the given path to an absolute file system path.
func Absolute(pathToResolve string, root string) (string, bool) {
	// Absolute path - append to root. This enables absolute path imports (eg, import '/lib/foo').
	if strings.HasPrefix(pathToResolve, "/") {
		pathToResolve = path.Join(root, pathToResolve)
	}

	return pathToResolve, true
}
