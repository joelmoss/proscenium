package plugin

import (
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"os"
	"path/filepath"
	"strings"
)

// The directory a bare import from a gem's file is resolved from, the one lookup policy of the
// bundling and unbundling plugins. resolver.Resolve, outside a build, deliberately keeps the app
// root for every bare specifier a gem does not map (see its doc comment).
//
//   - A gem with a dependency context (#154) resolves from that context alone; `mappedGem` names it.
//   - Any other gem's file resolves from the nearest directory, from the importer's up to the gem
//     root, whose node_modules holds the package, as Node would, but never above the gem root:
//     a node_modules above it (a home directory, a Ruby install) is not the gem's. With none, it
//     resolves from the app root, for the app's own packages and the peers a gem leaves to it.
//
// The bound picks the directory before esbuild runs rather than filtering what esbuild returns:
// a bundling build answers with real paths, and a package linked from outside both roots (`link:`,
// a pnpm store, a symlinked app root) is legitimately resolved there.
//
// `ok` is false for a specifier that is not bare, for an importer that is not a gem's file, and for
// a package the app installed inside a gem's root (utils.IsAppPackageFile), which resolve beside
// themselves as esbuild does.
func bareLookupDir(importer string, specifier string, cfg *types.ConfigT) (dir string, mappedGem string, ok bool) {
	pkg := utils.ExtractBareModule(specifier)
	if importer == "" || pkg == "" {
		return "", "", false
	}

	gem, found := utils.GemFromFsPath(importer, cfg)
	if !found || utils.IsAppPackageFile(importer, cfg) {
		return "", "", false
	}

	if contextDir, mapped := cfg.DependencyContexts[gem.Name]; mapped {
		return contextDir, gem.Name, true
	}

	gemRoot := strings.TrimSuffix(gem.Root, "/")
	for d := fsDir(importer); ; d = fsDir(d) {
		if info, err := os.Stat(utils.JoinFsPath(d, "node_modules", pkg)); err == nil && info.IsDir() {
			return d, "", true
		}
		if d == gemRoot || d == fsDir(d) {
			break
		}
	}

	return cfg.RootPath, "", true
}

// The parent of a slash-form file system path, in slash form on every platform.
func fsDir(p string) string {
	return filepath.ToSlash(filepath.Dir(p))
}
