package resolver

import (
	"encoding/json"
	"errors"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path"
	"reflect"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type Options struct {
	// The absolute file system path of the file doing the importing.
	Importer string

	// Import map as a string.
	ImportMap []byte
}

// Resolve the given `path` relative to the `root`, where the path is a URL path or bare specifier.
// This function is primarily intended to be used to resolve bare or NPM modules outside of any
// build.
//
// - filePath - The path to build relative to `root`.
//
// Returns an absolute URL path. That is, one that has a leading slash and can be appended to the
// app domain.
func Resolve(filePath string, options Options) (string, error) {
	// Parse the import map - if any.
	err := importmap.Parse(options.ImportMap)
	if err != nil {
		return "", errors.New("Failed to parse import map: " + err.Error())
	}

	// Look for a match in the import map
	resolvedImport, matched := importmap.Resolve(filePath, types.Config.RootPath)
	if matched {
		filePath = resolvedImport
	} else if path.IsAbs(filePath) && utils.HasExtension(filePath) {
		return filePath, nil
	}

	if utils.IsUrl(filePath) {
		return filePath, nil
	}

	if utils.PathIsRelative(filePath) {
		if options.Importer == "" {
			return "", errors.New("relative paths are not supported when an importer is not given")
		}

		return strings.TrimPrefix(path.Join(path.Dir(options.Importer), filePath), types.Config.RootPath), nil
	}

	// Replace leading slash with `./` for absolute paths.
	if path.IsAbs(filePath) {
		filePath = "." + filePath
	}

	logLevel := esbuild.LogLevelSilent
	if types.Config.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	result := esbuild.Build(esbuild.BuildOptions{
		EntryPoints:   []string{filePath},
		AbsWorkingDir: types.Config.RootPath,
		Format:        esbuild.FormatESModule,
		Conditions:    []string{types.Config.Environment.String(), "proscenium"},
		Write:         false,
		Metafile:      true,
		LogLevel:      logLevel,
		LogLimit:      1,

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
