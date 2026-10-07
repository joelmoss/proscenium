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
// file in the gem, or its root. A package the app installed is not the gem's, even inside the
// gem's root (see IsAppPackageFile).
func GemContext(fsPath string, cfg *types.ConfigT) (gem string, contextDir string, ok bool) {
	if len(cfg.DependencyContexts) == 0 || fsPath == "" {
		return "", "", false
	}

	ref, found := GemFromFsPath(fsPath, cfg)
	if !found || IsAppPackageFile(fsPath, cfg) {
		return "", "", false
	}

	contextDir, ok = cfg.DependencyContexts[ref.Name]

	return ref.Name, contextDir, ok
}

// Whether `fsPath` is a file of a package installed under the app root: below a `node_modules/`
// there, including a context's under `.proscenium/packages/`. That is every package the app
// installed, and also, for a gem developed in its own repository (`gemspec` in the Gemfile), every
// package under the gem's root, which is the app root. Their bare imports resolve beside them, as
// node resolution does: under pnpm and Bun a package's own dependencies are installed next to its
// real path, and walking up from there still reaches the app's node_modules for its peers.
//
// Only under the app root. A gem installed elsewhere that ships a package in its own node_modules
// keeps the fallbacks that hand it the app's peers, which walking up from the gem never reaches.
//
// The root is normalised as UrlPathFromFsPath normalises it, and nothing is concatenated: this
// runs for every import a build resolves. An unset root cleans to ".", which no absolute path
// starts with.
func IsAppPackageFile(fsPath string, cfg *types.ConfigT) bool {
	rel, ok := strings.CutPrefix(fsPath, strings.TrimSuffix(cleanFsPath(cfg.RootPath), "/"))

	return ok && strings.HasPrefix(rel, "/") && strings.Contains(rel, "/node_modules/")
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

	if spelled := SpellThroughRoot(real, cfg); spelled != real {
		return spelled
	}

	return appSpelling(fsPath, real, cfg)
}

// A real path under the app root's real path, spelled back through the root the app was given, so
// that it has a URL. The root itself may be a link, as a Capistrano-style `current` is, and on
// Windows a real path also expands 8.3 short names and takes the on-disk case. Otherwise `real`
// unchanged.
func SpellThroughRoot(real string, cfg *types.ConfigT) string {
	if root := realRoot(cfg.RootPath); root != "" && strings.HasPrefix(real, root+"/") {
		return strings.TrimSuffix(cfg.RootPath, "/") + real[len(root):]
	}

	return real
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
