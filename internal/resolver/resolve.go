package resolver

import (
	"errors"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"
	"strings"
)

type Options struct {
	// The path to build relative to `root`.
	Path string

	// The working directory.
	Root string

	// The path of the importing file or the current working file.
	Importer string

	// The environment (1 = development, 2 = test, 3 = production)
	Env types.Environment

	// Path to an import map (js or json), relative to the given root.
	ImportMapPath string

	// Import map as a string.
	ImportMap []byte

	Debug bool
}

func Resolve(options Options) (string, error) {
	os.Setenv("RAILS_ENV", options.Env.String())

	// Parse the import map - if any.
	imap, err := importmap.Parse(options.ImportMap, options.ImportMapPath, options.Root, options.Env)
	if err != nil {
		return "", errors.New("Failed to parse import map: " + err.Error())
	}

	if imap != nil {
		// Look for a match in the import map
		base := strings.TrimPrefix(options.Importer, options.Root)
		resolvedImport, matched := importmap.Resolve(options.Path, base, imap)
		if matched {
			return resolvedImport, nil
		}
	}

	return options.Path, nil
}

// Resolves the given path to an absolute file system path.
func Absolute(pathToResolve string, root string) (string, bool) {
	// Absolute path - append to root. This enables absolute path imports (eg, import '/lib/foo').
	if strings.HasPrefix(pathToResolve, "/") {
		pathToResolve = path.Join(root, pathToResolve)
	}

	return pathToResolve, true
}
