package utils

import (
	"fmt"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"path/filepath"
	"strings"
)

// Gem dependency contexts (#154): a participating gem's bare imports resolve from its context,
// `.proscenium/packages/<gem>/`, which the package manager installed its dependencies into.
// Nothing here does anything unless `cfg.DependencyContexts` is set, and Ruby sets it only for an
// app that has adopted them.

// The dependency context of the gem owning `fsPath`, when the map has that gem. `fsPath` is a
// file in the gem, or its root.
func GemContext(fsPath string, cfg *types.ConfigT) (gem string, contextDir string, ok bool) {
	if len(cfg.DependencyContexts) == 0 || fsPath == "" {
		return "", "", false
	}

	ref, found := GemFromFsPath(fsPath, cfg)
	if !found {
		return "", "", false
	}

	contextDir, ok = cfg.DependencyContexts[ref.Name]

	return ref.Name, contextDir, ok
}

// Logs, with cfg.Debug, a bare import resolved from a gem's context: which gem, what it imported and
// where that went.
func DebugContextRoute(cfg *types.ConfigT, gem string, specifier string, resolved string) {
	debug.Debug(cfg.Debug, "DependencyContext:routed", map[string]string{"gem": gem, "specifier": specifier, "path": resolved})
}

// A bare import from a mapped gem that its context cannot resolve. An error, never an external:
// falling back to the app's dependencies would hand the gem a version it did not declare.
func ContextMiss(gem string, specifier string) error {
	return fmt.Errorf("gem %q: could not resolve %q from its dependency context", gem, specifier)
}

// One real file is one module: under pnpm and Bun the app and a gem's context reach a shared
// package such as React through different links to the same file. While the map is set, a
// resolved path under `node_modules/` or `.proscenium/packages/` is replaced by its real path, so
// both importers get one URL. Anything else, a path that cannot be evaluated, or one whose real
// path has no URL (a store outside the app root, such as a global virtual store) is unchanged:
// the link path is still servable, the real path would not be.
//
// The app's own `link:`, `file:` and workspace packages keep their link paths too: no gem context
// shares them, and pages already reference those URLs.
func ContextRealPath(fsPath string, cfg *types.ConfigT) string {
	if len(cfg.DependencyContexts) == 0 ||
		(!strings.Contains(fsPath, "/node_modules/") && !strings.Contains(fsPath, "/.proscenium/packages/")) {
		return fsPath
	}

	for _, name := range cfg.AppLocalPackages {
		if strings.HasPrefix(fsPath, cfg.RootPath+"/node_modules/"+name+"/") {
			return fsPath
		}
	}

	real, err := filepath.EvalSymlinks(fsPath)
	if err != nil {
		return fsPath
	}

	real = filepath.ToSlash(real)
	if _, ok := UrlPathFromFsPath(real, cfg); !ok {
		return fsPath
	}

	return real
}
