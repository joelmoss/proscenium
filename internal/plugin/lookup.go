package plugin

import (
	"encoding/json"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"
)

// The directories, in order, that a bare import from a gem's file is resolved from: the one lookup
// policy of the bundling and unbundling plugins. A caller tries each until one resolves.
// resolver.Resolve, outside a build, deliberately keeps the app root for every bare specifier a gem
// does not map (see its doc comment).
//
//   - A gem with a dependency context (#154) resolves from that context alone; `mappedGem` names it.
//   - A file of a package the gem ships in its own node_modules resolves beside itself first, as
//     Node does, so the package's own dependencies (pnpm puts them beside its real path), `browser`
//     and `imports` fields apply; then from the app root, for a peer the package leaves to the app.
//     esbuild walks up from there unbounded, as Node would, so a node_modules above the gem root
//     can answer first for a package that neither the gem nor its packages have.
//   - A package the gem lists in its package.json `peerDependencies` resolves from the app root
//     first, from any file under the gem root, then as below. A peer is the app's to provide, and
//     a gem developed locally often has its own copy installed (pnpm installs peers by default):
//     taking that copy would put two Reacts on the page.
//   - Any other file of a gem (its own source) resolves from the nearest directory, from the
//     importer's up to the gem root, whose node_modules holds the package, but never above the gem
//     root: a node_modules above it (a home directory, a Ruby install) is not the gem's. With none,
//     from the app root, for the app's own packages and the peers a gem leaves to it. That moves
//     where resolution starts, so the gem's own package.json `browser` map and self-references by
//     its npm name do not apply to such an import; a gem that needs them maps a context (#154).
//
// The bound picks where esbuild starts rather than filtering what it returns: a bundling build
// answers with real paths, and a package linked from outside both roots (`link:`, a pnpm store, a
// symlinked app root) is legitimately resolved there.
//
// `dirs` is nil, and the import resolves from esbuild's own ResolveDir, for:
//   - a specifier that is not a package name: relative, a `#` subpath import (which belongs to the
//     importer's own package.json), or one with a `..` segment;
//   - an importer that is not a gem's file, or is a package the app installed inside a gem's root
//     (utils.IsAppPackageFile), which resolves beside itself like any of the app's packages.
func bareLookupDirs(importer string, specifier string, cfg *types.ConfigT) (dirs []string, mappedGem string) {
	pkg := utils.ExtractBareModule(specifier)
	if importer == "" || pkg == "" || strings.HasPrefix(pkg, "#") || strings.Contains(pkg, "..") {
		return nil, ""
	}

	gem, found := utils.GemFromFsPath(importer, cfg)
	if !found || utils.IsAppPackageFile(importer, cfg) {
		return nil, ""
	}

	if contextDir, mapped := cfg.DependencyContexts[gem.Name]; mapped {
		return []string{contextDir}, gem.Name
	}

	gemRoot := strings.TrimSuffix(gem.Root, "/")
	dirs = gemLookupDirs(importer, gemRoot, pkg, cfg.RootPath)
	if dirs[0] != cfg.RootPath && isGemPeer(gemRoot, pkg) {
		dirs = append([]string{cfg.RootPath}, slices.DeleteFunc(dirs, func(d string) bool {
			return d == cfg.RootPath
		})...)
	}

	return dirs, ""
}

// The lookup directories for a package that is not a peer of an unmapped gem (bareLookupDirs).
func gemLookupDirs(importer string, gemRoot string, pkg string, appRoot string) []string {
	if strings.Contains(strings.TrimPrefix(importer, gemRoot), "/node_modules/") {
		return []string{fsDir(importer), appRoot}
	}

	for d := fsDir(importer); ; d = fsDir(d) {
		if hasPackage(utils.JoinFsPath(d, "node_modules", pkg)) {
			return []string{d}
		}
		if d == gemRoot || d == fsDir(d) {
			break
		}
	}

	return []string{appRoot}
}

// A gem's `peerDependencies`, by the path of its package.json. An entry is kept until the file's
// modification time or size changes, so a long-running server sees an edit.
var gemPeers sync.Map

type gemPeersEntry struct {
	modTime time.Time
	size    int64
	peers   map[string]any
}

// Whether the package.json at `gemRoot` lists `pkg` in its `peerDependencies`. A gem with no
// package.json, or one that is not valid JSON, has no peers.
func isGemPeer(gemRoot string, pkg string) bool {
	path := filepath.FromSlash(utils.JoinFsPath(gemRoot, "package.json"))
	info, err := os.Stat(path)
	if err != nil {
		return false
	}

	if cached, ok := gemPeers.Load(path); ok {
		entry := cached.(gemPeersEntry)
		if entry.modTime.Equal(info.ModTime()) && entry.size == info.Size() {
			_, peer := entry.peers[pkg]

			return peer
		}
	}

	var manifest struct {
		PeerDependencies map[string]any `json:"peerDependencies"`
	}
	data, err := os.ReadFile(path)
	if err == nil {
		err = json.Unmarshal(data, &manifest)
	}
	if err != nil {
		manifest.PeerDependencies = nil
	}
	gemPeers.Store(path, gemPeersEntry{modTime: info.ModTime(), size: info.Size(), peers: manifest.PeerDependencies})
	_, peer := manifest.PeerDependencies[pkg]

	return peer
}

// Whether node_modules holds `base`: a package directory, or a file module (`node_modules/tiny.js`
// answers `import "tiny"`), with any extension esbuild's lookup tries.
func hasPackage(base string) bool {
	if _, err := os.Stat(base); err == nil {
		return true
	}
	for _, ext := range []string{".tsx", ".ts", ".jsx", ".js", ".mjs", ".cjs", ".css", ".json"} {
		if info, err := os.Stat(base + ext); err == nil && info.Mode().IsRegular() {
			return true
		}
	}

	return false
}

// The parent of a slash-form file system path, in slash form on every platform.
func fsDir(p string) string {
	return filepath.ToSlash(filepath.Dir(p))
}
