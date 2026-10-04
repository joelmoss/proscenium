package utils

import (
	"fmt"
	"joelmoss/proscenium/internal/types"
	"path/filepath"
	"strings"
)

// The Stage A resolver seam for #154 (see test/package_manager/stage_a/README.md). Disposable:
// Stage C replaces it with the real context map, built by Ruby from Bundler. Nothing here does
// anything unless `cfg.StageAContexts` is set, and only the Stage A proof sets it.

// The dependency context of the gem owning `fsPath`, when the seam maps that gem. `fsPath` is a
// file in the gem, or its root.
func StageAContext(fsPath string, cfg *types.ConfigT) (gem string, contextDir string, ok bool) {
	if len(cfg.StageAContexts) == 0 || fsPath == "" {
		return "", "", false
	}

	ref, found := GemFromFsPath(fsPath, cfg)
	if !found {
		return "", "", false
	}

	contextDir, ok = cfg.StageAContexts[ref.Name]

	return ref.Name, contextDir, ok
}

// A bare import from a mapped gem that its context cannot resolve. An error, never an external:
// falling back to the app's dependencies would hand the gem a version it did not declare.
func StageAMiss(gem string, specifier string) error {
	return fmt.Errorf("gem %q: could not resolve %q from its dependency context", gem, specifier)
}

// One real file is one module: under pnpm and Bun the app and a gem's context reach a shared
// package such as React through different links to the same file. While the seam is on, a
// resolved path under `node_modules/` or `.proscenium/packages/` is replaced by its real path, so
// both importers get one URL. Anything else, or a path that cannot be evaluated, is unchanged.
func StageARealPath(fsPath string, cfg *types.ConfigT) string {
	if len(cfg.StageAContexts) == 0 ||
		(!strings.Contains(fsPath, "/node_modules/") && !strings.Contains(fsPath, "/.proscenium/packages/")) {
		return fsPath
	}

	real, err := filepath.EvalSymlinks(fsPath)
	if err != nil {
		return fsPath
	}

	return filepath.ToSlash(real)
}
