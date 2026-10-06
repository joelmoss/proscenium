package utils

import (
	"fmt"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"path/filepath"
	"strings"
	"sync"
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
// path has no URL (a store outside the app root, such as a global virtual store) keeps a link
// path, which is servable where the real path would not be: the app's, where it has one.
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
	if _, ok := UrlPathFromFsPath(real, cfg); ok {
		return real
	}

	// The root itself may be a link, as a Capistrano-style `current` is: the real path is then
	// under the release directory, and is spelled back through the root the app was given.
	if root := realRoot(cfg.RootPath); root != "" && strings.HasPrefix(real, root+"/") {
		return strings.TrimSuffix(cfg.RootPath, "/") + real[len(root):]
	}

	return appSpelling(fsPath, real, cfg)
}

// A context's link to a file outside the app root, as pnpm's global virtual store makes, spelled
// as the app's own link when that reaches the same file: the real path has no URL, and two link
// URLs would load one module twice. Otherwise `fsPath` unchanged.
func appSpelling(fsPath string, real string, cfg *types.ConfigT) string {
	contexts := strings.TrimSuffix(cfg.RootPath, "/") + "/.proscenium/packages/"
	rest, ok := strings.CutPrefix(fsPath, contexts)
	if !ok {
		return fsPath
	}
	_, inside, ok := strings.Cut(rest, "/node_modules/")
	if !ok {
		return fsPath
	}

	app := strings.TrimSuffix(cfg.RootPath, "/") + "/node_modules/" + inside
	if appReal, err := filepath.EvalSymlinks(app); err == nil && filepath.ToSlash(appReal) == real {
		return app
	}

	return fsPath
}

var realRoots sync.Map

// The real path of the app root, resolved once per root; "" when it cannot be resolved.
func realRoot(root string) string {
	if real, ok := realRoots.Load(root); ok {
		return real.(string)
	}

	real, err := filepath.EvalSymlinks(root)
	if err != nil {
		real = ""
	}
	real = strings.TrimSuffix(filepath.ToSlash(real), "/")
	realRoots.Store(root, real)
	return real
}
