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
var Dirname = api.Plugin{
	Name: "dirname",
	Setup: func(build api.PluginBuild) {
		build.OnLoad(api.OnLoadOptions{Filter: `\.(jsx?|tsx?)$`},
			func(args api.OnLoadArgs) (api.OnLoadResult, error) {
				debug.Debug("OnLoad:begin", args)

				// Skip npm packages in node_modules.
				if strings.Contains(filepath.ToSlash(args.Path), "/node_modules/") {
					debug.Debug(strings.Contains(filepath.ToSlash(args.Path), "/node_modules/"))
					return api.OnLoadResult{}, nil
				}

				var relPath string

				if gemName, gemPath, ok := utils.PathIsRubyGem(args.Path); ok {
					// Rubygem file — use @rubygems/<name>/... path.
					suffix := strings.TrimPrefix(filepath.ToSlash(args.Path), filepath.ToSlash(gemPath))
					relPath = types.RubyGemsScope + gemName + suffix
				} else if cutPath, ok := strings.CutPrefix(filepath.ToSlash(args.Path), filepath.ToSlash(types.Config.RootPath)); ok {
					// File inside the project root — use root-relative path.
					relPath = cutPath
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
