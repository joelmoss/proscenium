package plugin

import (
	"encoding/json"
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"
	"strings"
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

var (
	i18nCachedResult *string
	i18nFileMtimes   map[string]time.Time
	i18nDirMtime     time.Time
)

var I18n = esbuild.Plugin{
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
				// In production, return cached result immediately if available.
				if types.Config.Environment == types.ProdEnv && i18nCachedResult != nil {
					return esbuild.OnLoadResult{
						Contents: i18nCachedResult,
						Loader:   esbuild.LoaderJSON,
					}, nil
				}

				// In non-production, check if locale files have changed via mtimes
				// before doing any expensive work.
				if i18nCachedResult != nil {
					changed := false

					// Check directory mtime for added/removed files.
					dirInfo, err := os.Stat(root)
					if err != nil || !dirInfo.ModTime().Equal(i18nDirMtime) {
						changed = true
					}

					// Check individual file mtimes for content changes.
					if !changed {
						for path, mtime := range i18nFileMtimes {
							info, err := os.Stat(path)
							if err != nil || !info.ModTime().Equal(mtime) {
								changed = true
								break
							}
						}
					}

					if !changed {
						return esbuild.OnLoadResult{
							Contents: i18nCachedResult,
							Loader:   esbuild.LoaderJSON,
						}, nil
					}
				}

				// Record directory mtime.
				if dirInfo, err := os.Stat(root); err == nil {
					i18nDirMtime = dirInfo.ModTime()
				}

				// Read locale files using os.ReadDir instead of filepath.Glob.
				entries, err := os.ReadDir(root)
				if err != nil {
					empty := "{}"
					i18nCachedResult = &empty
					return esbuild.OnLoadResult{
						Contents: i18nCachedResult,
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

					// Track file mtime for change detection.
					if info, err := entry.Info(); err == nil {
						fileMtimes[path] = info.ModTime()
					}

					data, err := os.ReadFile(path)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					var yamlData map[string]any
					if err := yaml.Unmarshal(data, &yamlData); err != nil {
						return esbuild.OnLoadResult{}, err
					}

					contents = mergemap.Merge(contents, yamlData)
				}

				i18nFileMtimes = fileMtimes

				// Apply camelCase transform directly on the YAML map, then marshal
				// to JSON once — avoiding the redundant JSON round-trip.
				transformed := camelCaseKeys(contents)

				b, err := json.Marshal(transformed)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				result := string(b)
				i18nCachedResult = &result

				return esbuild.OnLoadResult{
					Contents: i18nCachedResult,
					Loader:   esbuild.LoaderJSON,
				}, nil
			})
	},
}
