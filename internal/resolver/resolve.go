package resolver

import (
	"encoding/json"
	"errors"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path"
	"path/filepath"
	"reflect"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

// Resolve the given `filePath` relative to the root, where the filePath is a URL path or bare
// specifier. This function is primarily intended to be used to resolve bare or NPM modules outside
// of any build.
//
// If `importer` is given, then the `filePath` is resolved relative to the `importer` path.
//
// This is used to resolve paths that are not part of the build process. It does not actually build
// the file, but returns the URL path that will then usually be requested and served by the Rails
// middleware.
//
// Returns an absolute URL path. That is, one that has a leading slash and can be appended to the
// app domain.
func Resolve(filePath string, importer string) (string, error) {
	rootPath := types.Config.RootPath

	debug.Debug("Resolve:begin", map[string]string{"filePath": filePath, "importer": importer})

	// Look for a match in the import map
	filePath, imErr := importmap.Resolve(filePath, rootPath)
	if imErr != nil {
		return returnResolve(filePath, imErr)
	} else if path.IsAbs(filePath) {
		if _, ok := utils.HasExtension(filePath); ok {
			return returnResolve(filePath, nil)
		}
	}

	if utils.IsUrl(filePath) {
		return returnResolve(filePath, nil)
	}

	if utils.PathIsRelative(filePath) {
		if importer == "" {
			return returnResolve("", errors.New("relative paths are not supported when an importer is not given"))
		}

		filePath = path.Join(path.Dir(importer), filePath)

		// TODO: while filePath is relative, the importer could be a ruby gem. Check now, and return
		// correct path (beginning /node_modules/@rubygems/...)
		gemName, gemPath, found := utils.PathIsRubyGem(filePath)
		if found {
			return returnResolve("/node_modules/"+types.RubyGemsScope+gemName+strings.TrimPrefix(filePath, gemPath), nil)
		}

		return returnResolve(strings.TrimPrefix(filePath, rootPath), nil)
	}

	gemName := ""
	if utils.IsRubyGem(filePath) {
		var err error
		gemName, rootPath, err = utils.ResolveRubyGem(filePath)
		if err != nil {
			return returnResolve(filePath, err)
		}

		pathSuffix := utils.RemoveRubygemPrefix(filePath, gemName)

		if _, ok := utils.HasExtension(filePath); ok {
			return returnResolve("/node_modules/"+filePath, nil)
		}

		if pathSuffix == "" {
			filePath = "./"
		} else {
			filePath = pathSuffix
		}
	}

	if !utils.IsBareModule(filePath) {
		if _, ok := utils.HasExtension(filePath); ok {
			return returnResolve(filePath, nil)
		}
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
		EntryPoints:      []string{filePath},
		AbsWorkingDir:    rootPath,
		Format:           esbuild.FormatESModule,
		Conditions:       []string{types.Config.Environment.String(), "proscenium"},
		Write:            false,
		Metafile:         true,
		LogLevel:         logLevel,
		LogLimit:         1,
		PreserveSymlinks: true,

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},
	})

	if len(result.Errors) > 0 {
		return returnResolve("", errors.New(result.Errors[0].Text))
	}

	var metadata struct{ Inputs map[string]any }
	err := json.Unmarshal([]byte(result.Metafile), &metadata)
	if err != nil {
		return returnResolve("", err)
	}

	filePath = reflect.ValueOf(metadata.Inputs).MapKeys()[0].String()

	if gemName != "" {
		return returnResolve("/node_modules/"+types.RubyGemsScope+gemName+"/"+filePath, nil)
	}

	return returnResolve("/"+filePath, nil)
}

// Resolve the given `filePath` relative to the root, where the `filePath` is a URL path or bare
// specifier, It returns an absolute file system path, and is used to resolve CSS mixins.
//
// @see Resolve()
func ResolveToFSPath(filePath string, importer string) (string, error) {
	urlPath, err := Resolve(filePath, importer)
	if err != nil {
		return "", err
	}

	debug.Debug(urlPath)

	// We need the absolute file system path
	isRubyGem := false
	relativePath := strings.TrimPrefix(urlPath, "/node_modules/")
	if utils.IsRubyGem(relativePath) {
		gemName, gemPath, err := utils.ResolveRubyGem(relativePath)
		if err != nil {
			return "", err
		}

		isRubyGem = true
		suffix := utils.RemoveRubygemPrefix(relativePath, gemName)
		urlPath = filepath.Join(gemPath, suffix)
	}

	if !isRubyGem {
		urlPath = path.Join(types.Config.RootPath, urlPath)
	}

	return urlPath, nil
}

func returnResolve(filePath string, err error) (string, error) {
	if debug.Enabled {
		errStr := ""
		if err != nil {
			errStr = err.Error()
		}
		debug.Debug("Resolve:end", map[string]string{"filePath": filePath, "error": errStr})
	}

	return filePath, err
}
