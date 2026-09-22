package plugin

import (
	"fmt"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path"
	"path/filepath"
	"strings"

	"github.com/joelmoss/esbuild-internal/api"
)

// Dirname provides `__filename` and `__dirname` constants to JS/TS files, similar to Node.js. The
// values are root-relative paths with a leading `/`, or resolved URL paths for rubygem files.
func Dirname(cfg *types.ConfigT) api.Plugin {
	return api.Plugin{
		Name: "dirname",
		Setup: func(build api.PluginBuild) {
			build.OnLoad(api.OnLoadOptions{Filter: `\.(jsx?|tsx?)$`},
				func(args api.OnLoadArgs) (api.OnLoadResult, error) {
					args.Path = filepath.ToSlash(args.Path)

					debug.Debug(cfg.Debug, "OnLoad:begin", args)

					// Skip npm packages in node_modules.
					if strings.Contains(args.Path, "/node_modules/") {
						debug.Debug(cfg.Debug, strings.Contains(args.Path, "/node_modules/"))
						return api.OnLoadResult{}, nil
					}

					var relPath string

					// The gem branch stays separate rather than folding into UrlPathFromFsPath:
					// __filename for a gem file is `@rubygems/<name>/...`, without the
					// `/node_modules/` prefix the served URL carries.
					//
					// The app-root branch was a bare CutPrefix, which had no boundary - a sibling
					// directory sharing the root's name prefix was treated as inside it.
					if ref, ok := utils.GemFromFsPath(args.Path, cfg); ok {
						// Rubygem file — use @rubygems/<name>/... path.
						relPath = types.RubyGemsScope + ref.Name + ref.Suffix
					} else if urlPath, ok := utils.UrlPathFromFsPath(args.Path, cfg); ok {
						// File inside the project root — use root-relative path.
						relPath = urlPath
					} else {
						return api.OnLoadResult{}, nil
					}

					dir := path.Dir(relPath)
					prepend := fmt.Sprintf("const __filename = %q, __dirname = %q;\n", relPath, dir)

					return api.OnLoadResult{
						Prepend: &prepend,
					}, nil
				})
		},
	}
}
