package resolver

import (
	"encoding/json"
	"errors"
	"fmt"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path"
	"path/filepath"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

// Resolve the given `filePath` relative to the root, where the filePath is a URL path or bare
// specifier.
//
// This function is primarily intended to be used to resolve bare or NPM modules outside
// of any build. It is used to resolve paths that are not part of the build process. It does not
// actually build the file, but returns the URL path that will then usually be requested and served
// by the Rails middleware.
//
// If `importer` is given, then the `filePath` is resolved relative to the `importer` path. The
// importer is the absolute file system path of the file doing the importing.
//
// Returns an URL path (has a leading slash and can be appended to the app domain), and the absolute
// file system path. Every exit knows both halves and returns both; neither is re-derived from the
// other. `<key>` below is the one input esbuild's metafile records for the resolve-only build.
//
//	input                              urlPath                                 absPath
//	https://…                          the URL                                 "" (no file)
//	./x, importer in a gem             /node_modules/@rubygems/<gem><rest>     the joined path
//	./x, importer under the root       joined path minus the root              the joined path
//	./x, importer elsewhere            error
//	@rubygems/<gem>/x.js               /node_modules/@rubygems/<gem>/x.js      <gem root>/x.js
//	  (also with a leading "/", "node_modules/" or "unbundle:" prefix)
//	@rubygems/<gem>/x  (no extension)  /node_modules/@rubygems/<gem>/<key>     <gem root>/<key>
//	/lib/x.js                          /lib/x.js                               <root>/lib/x.js
//	/lib/x, pkg  (no extension, bare)  /<key>                                  <root>/<key>
//
// A panic anywhere below, on this goroutine, is returned as the error rather than taking down the
// Ruby process that called in. See BuildToString.
func Resolve(filePath string, importer string, cfg *types.ConfigT) (urlPath string, absPath string, err error) {
	if perr := utils.Recover(func() {
		urlPath, absPath, err = resolve(filePath, importer, cfg)
	}); perr != nil {
		// Ruby's ResolveError takes a string, so the stack rides in the message itself.
		return "", "", perr
	}

	return urlPath, absPath, err
}

func resolve(filePath string, importer string, cfg *types.ConfigT) (urlPath string, absPath string, err error) {
	rootPath := cfg.RootPath

	debug.Debug(cfg.Debug, "Resolve:begin", map[string]string{"filePath": filePath, "importer": importer})

	if utils.IsUrl(filePath) {
		// A URL has no file on disk.
		return returnResolve(filePath, "", nil, cfg)
	}

	if utils.PathIsRelative(filePath) {
		if importer == "" {
			return returnResolve("", "", errors.New("relative paths are not supported when an importer is not given"), cfg)
		}

		joined := utils.JoinFsPath(path.Dir(importer), filePath)

		// Under neither root, the path used to go out unchanged: an absolute file system path
		// as a URL. The error names the import as written and the importer's file name, not the
		// joined path: it reaches browsers, logs and error trackers, and a machine path is not
		// theirs to see (see 6e046d87).
		urlPath, ok := utils.UrlPathFromFsPath(joined, cfg)
		if !ok {
			return returnResolve("", "", fmt.Errorf("%q from %q is outside the app root and every bundled gem", filePath, path.Base(importer)), cfg)
		}

		return returnResolve(urlPath, joined, nil, cfg)
	}

	// The served form, `/node_modules/@rubygems/…`, is parsed here too. It used to miss the gem
	// branch, take the absolute-path exit, and rely on the URL string being parsed a second time
	// at the end to find the gem's file.
	gem, isGem, err := utils.GemFromSpecifier(filePath, cfg)
	if err != nil {
		return returnResolve("", "", err, cfg)
	}

	if isGem {
		rootPath = gem.Root

		if _, ok := utils.HasExtension(filePath); ok {
			return returnResolve(gem.UrlPath(), utils.JoinFsPath(gem.Root, gem.Suffix), nil, cfg)
		}

		if gem.Suffix == "" {
			filePath = "./"
		} else {
			filePath = "." + gem.Suffix
		}
	} else if !utils.IsBareModule(filePath) {
		if _, ok := utils.HasExtension(filePath); ok {
			// A Windows drive or UNC path, which names a file rather than a URL. Ruby maps one under
			// Rails.root itself, so this is reached when that prefix match missed. Treated as the
			// relative branch above treats a joined path: served from the URL it maps to, or
			// refused - it used to go out as the URL, with the drive joined onto the root a second
			// time for the file. A volume name rather than the absoluteness predicates, because a
			// UNC path is "//"-rooted and looks URL-rooted to them; outside Windows it is always
			// empty, so nothing else changes.
			if filepath.VolumeName(filePath) != "" {
				urlPath, ok := utils.UrlPathFromFsPath(filePath, cfg)
				if !ok {
					// filepath.Base, not path.Base: this can be a backslash path, and path.Base would
					// hand the whole machine path to the error, which reaches browsers.
					return returnResolve("", "", fmt.Errorf("%q is outside the app root and every bundled gem", filepath.Base(filePath)), cfg)
				}

				return returnResolve(urlPath, utils.JoinFsPath(filePath), nil, cfg)
			}

			return returnResolve(filePath, utils.JoinFsPath(rootPath, filePath), nil, cfg)
		}

		// URL-root, not fs-absolute: a drive path turned into "./" here would become ".C:/...".
		if utils.UrlPathIsAbs(filePath) {
			filePath = "." + filePath
		}
	}

	logLevel := esbuild.LogLevelWarning
	if cfg.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	result := esbuild.Build(esbuild.BuildOptions{
		EntryPoints:      []string{filePath},
		AbsWorkingDir:    rootPath,
		Format:           esbuild.FormatESModule,
		Conditions:       []string{cfg.Environment.String(), "proscenium"},
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
		// Text plus notes: a panic the esbuild fork recovered in a plugin carries its stack in a
		// note, and Ruby's ResolveError only takes a string.
		return returnResolve("", "", errors.New(utils.MessageText(result.Errors[0])), cfg)
	}

	var metadata struct{ Inputs map[string]any }
	jsonErr := json.Unmarshal([]byte(result.Metafile), &metadata)
	if jsonErr != nil {
		return returnResolve("", "", jsonErr, cfg)
	}

	// The build above does not bundle, so esbuild parses the entry point and nothing else: one
	// input, whose key is the resolved path relative to `rootPath`. Taking "the" key from a map
	// without this check would answer with a random one the day that assumption breaks.
	if len(metadata.Inputs) != 1 {
		return returnResolve("", "", fmt.Errorf("expected one input for %q, esbuild reported %d", filePath, len(metadata.Inputs)), cfg)
	}

	key := ""
	for k := range metadata.Inputs {
		key = k
	}

	if isGem {
		return returnResolve(utils.GemRef{Name: gem.Name, Root: gem.Root, Suffix: "/" + key}.UrlPath(), utils.JoinFsPath(gem.Root, key), nil, cfg)
	}

	return returnResolve("/"+key, utils.JoinFsPath(rootPath, key), nil, cfg)
}

func returnResolve(urlPath string, absPath string, err error, cfg *types.ConfigT) (string, string, error) {
	errStr := ""
	if err != nil {
		errStr = err.Error()
	}

	debug.Debug(cfg.Debug, "Resolve:end", map[string]string{"urlPath": urlPath, "absPath": absPath, "error": errStr})

	if err != nil {
		return "", "", err
	}

	return urlPath, absPath, nil
}
