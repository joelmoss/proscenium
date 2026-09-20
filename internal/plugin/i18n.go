package plugin

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	esbuild "github.com/joelmoss/esbuild-internal/api"
	"github.com/peterbourgon/mergemap"
	yaml "gopkg.in/yaml.v3"
)

// toCamelCase converts underscore/hyphen/space-separated strings to camelCase.
func toCamelCase(s string) string {
	parts := strings.FieldsFunc(s, func(r rune) bool {
		return r == '_' || r == '-' || r == ' '
	})
	if len(parts) == 0 {
		return s
	}
	for i := range parts {
		if parts[i] == "" {
			continue
		}
		if i == 0 {
			parts[i] = strings.ToLower(parts[i][:1]) + parts[i][1:]
		} else {
			parts[i] = strings.ToUpper(parts[i][:1]) + parts[i][1:]
		}
	}
	return strings.Join(parts, "")
}

// camelCaseKeys recursively transforms all map keys to camelCase.
func camelCaseKeys(v any) any {
	switch vt := v.(type) {
	case map[string]any:
		out := make(map[string]any, len(vt))
		for k, val := range vt {
			out[toCamelCase(k)] = camelCaseKeys(val)
		}
		return out
	case []any:
		for i, elem := range vt {
			vt[i] = camelCaseKeys(elem)
		}
		return vt
	default:
		return v
	}
}

// Memoised per locales directory rather than per process, following the same shape as
// `svgCaches`: `root` is derived from the build's own working directory, and one process can build
// several apps - the test suite does. Sharing one payload between roots meant whichever built
// first won for both.
var (
	i18nCachesMutex sync.Mutex
	i18nCaches      = map[string]*i18nCache{}
)

// A complete answer, published in one store. The three fields used to be three bare globals with
// three independent write points, and the directory mtime was written BEFORE the locale files were
// read - so a file that failed to parse left a new directory mtime beside the old payload, and
// nothing short of a restart could dislodge it.
//
// Immutable once published. Readers take the pointer under the mutex and then read the snapshot
// without holding it, which is only safe while nothing mutates a published one - so replace a
// snapshot rather than, say, adding an entry to `fileMtimes`.
type i18nCache struct {
	result     *string
	dirMtime   time.Time
	fileMtimes map[string]time.Time
}

// The cause of a filesystem error, without the absolute path the OS names in it. Build errors
// reach the browser's error overlay, the logs and any error tracker, so the machine's paths stay
// out of them - `6e046d87` removed a gem's install path for the same reason.
func osCause(err error) error {
	var pathErr *fs.PathError
	if errors.As(err, &pathErr) {
		return pathErr.Err
	}

	return err
}

func i18nCacheFor(root string) *i18nCache {
	i18nCachesMutex.Lock()
	defer i18nCachesMutex.Unlock()

	return i18nCaches[root]
}

// Publishes fresh only if the snapshot this build decided against is still the published one. Two
// builds for one root can be in flight - the daemon's worker pool and esbuild's own plugin
// goroutines both produce that - and the assignment alone ordered the write, not the generations:
// a slow build published its older payload over a newer one. The first to publish now wins, and
// the loser returns its own payload rather than overwriting a generation newer than what it read.
// In development the next build corrects the store, because the winner's file mtimes are compared
// against disk. Production has no such correction - the early return above serves the published
// snapshot without a freshness check - so a refused newer payload would stick there. It takes
// locale files changing while two cold builds for one root are mid-load, which a deployed app,
// whose files do not move during a build, does not do.
//
// gstack-shortcut(dec-760a3bbc): no direct test - this is unexported and test/ is a separate
// package. Upgrade when internal/ gets a test package (AUDIT.md pattern P7 needs one anyway), or
// when this is reported wrong.
func storeI18nCache(root string, prev, fresh *i18nCache) {
	i18nCachesMutex.Lock()
	defer i18nCachesMutex.Unlock()

	if i18nCaches[root] != prev {
		return
	}

	i18nCaches[root] = fresh
}

func I18n(cfg *types.ConfigT) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "i18n",
		Setup: func(build esbuild.PluginBuild) {
			cwd := build.InitialOptions.AbsWorkingDir
			root := filepath.Join(cwd, "config", "locales")

			build.OnResolve(esbuild.OnResolveOptions{Filter: `^proscenium/i18n$`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					return esbuild.OnResolveResult{
						Path:      args.Path,
						Namespace: "i18n",
					}, nil
				})

			build.OnLoad(esbuild.OnLoadOptions{Filter: `\.*`, Namespace: "i18n"},
				func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
					// Read the snapshot once. Everything below decides against this one value, so it
					// cannot change underfoot mid-decision.
					cache := i18nCacheFor(root)

					// In production, return cached result immediately if available.
					if cfg.Environment == types.ProdEnv && cache != nil {
						return esbuild.OnLoadResult{
							Contents: cache.result,
							Loader:   esbuild.LoaderJSON,
						}, nil
					}

					// In non-production, check if locale files have changed via mtimes
					// before doing any expensive work.
					if cache != nil {
						changed := false

						// Check directory mtime for added/removed files.
						dirInfo, err := os.Stat(root)
						if err != nil || !dirInfo.ModTime().Equal(cache.dirMtime) {
							changed = true
						}

						// Check individual file mtimes for content changes.
						if !changed {
							for path, mtime := range cache.fileMtimes {
								info, err := os.Stat(path)
								if err != nil || !info.ModTime().Equal(mtime) {
									changed = true
									break
								}
							}
						}

						if !changed {
							return esbuild.OnLoadResult{
								Contents: cache.result,
								Loader:   esbuild.LoaderJSON,
							}, nil
						}
					}

					// Read the directory mtime into a local. It is published below along with the
					// payload it describes, and only once that payload exists - recording it here
					// used to hide every later failure from the next build's change detection.
					var dirMtime time.Time
					if dirInfo, err := os.Stat(root); err == nil {
						dirMtime = dirInfo.ModTime()
					}

					// Read locale files using os.ReadDir instead of filepath.Glob.
					entries, err := os.ReadDir(root)
					if err != nil {
						// An app with no config/locales is ordinary: it gets an empty payload.
						// Anything else - a directory that stats but refuses to list, an I/O
						// error - is reported. Publishing {} for those satisfied the mtime
						// comparison below on every later build, so the empty payload was served
						// for the life of the process and the error was never seen.
						if !errors.Is(err, fs.ErrNotExist) {
							return esbuild.OnLoadResult{}, fmt.Errorf(
								"could not read config/locales: %w", osCause(err))
						}

						empty := "{}"
						fresh := &i18nCache{
							result:     &empty,
							dirMtime:   dirMtime,
							fileMtimes: map[string]time.Time{},
						}
						storeI18nCache(root, cache, fresh)

						return esbuild.OnLoadResult{
							Contents: fresh.result,
							Loader:   esbuild.LoaderJSON,
						}, nil
					}

					fileMtimes := make(map[string]time.Time, len(entries))
					contents := map[string]any{}

					for _, entry := range entries {
						if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".yml") {
							continue
						}

						path := filepath.Join(root, entry.Name())

						// Track file mtime for change detection. A failure here used to be
						// skipped, which put the file in the payload and outside the detector:
						// the loop below merges it either way, and change detection only stats
						// files it recorded, so later edits to it never invalidated the snapshot.
						//
						// gstack-shortcut(dec-760a3bbc): unexercised by any test - the branch
						// needs a file to vanish between the directory listing and this stat,
						// which a spec cannot schedule without a seam. Upgrade when this loop is
						// extracted for other reasons.
						info, err := entry.Info()
						if err != nil {
							return esbuild.OnLoadResult{}, fmt.Errorf(
								"could not read config/locales/%s: %w", entry.Name(), osCause(err))
						}
						fileMtimes[path] = info.ModTime()

						data, err := os.ReadFile(path)
						if err != nil {
							return esbuild.OnLoadResult{}, fmt.Errorf(
								"could not read config/locales/%s: %w", entry.Name(), osCause(err))
						}

						var yamlData map[string]any
						if err := yaml.Unmarshal(data, &yamlData); err != nil {
							return esbuild.OnLoadResult{}, err
						}

						contents = mergemap.Merge(contents, yamlData)
					}

					// Apply camelCase transform directly on the YAML map, then marshal
					// to JSON once — avoiding the redundant JSON round-trip.
					transformed := camelCaseKeys(contents)

					b, err := json.Marshal(transformed)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					// The single success publish. Every failure above returns without one, leaving
					// the previous snapshot - stale, but wholly consistent, and superseded by the
					// next build that finds a changed mtime.
					result := string(b)
					fresh := &i18nCache{
						result:     &result,
						dirMtime:   dirMtime,
						fileMtimes: fileMtimes,
					}
					storeI18nCache(root, cache, fresh)

					return esbuild.OnLoadResult{
						Contents: fresh.result,
						Loader:   esbuild.LoaderJSON,
					}, nil
				})
		},
	}
}
