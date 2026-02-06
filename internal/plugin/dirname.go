package plugin

import (
	"fmt"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"os"
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
				if strings.Contains(args.Path, "/node_modules/") {
					debug.Debug(strings.Contains(args.Path, "/node_modules/"))
					return api.OnLoadResult{}, nil
				}

				var relPath string

				if gemName, gemPath, ok := utils.PathIsRubyGem(args.Path); ok {
					// Rubygem file — use @rubygems/<name>/... path.
					suffix := strings.TrimPrefix(args.Path, gemPath)
					relPath = types.RubyGemsScope + gemName + suffix
				} else if cutPath, ok := strings.CutPrefix(args.Path, types.Config.RootPath); ok {
					// File inside the project root — use root-relative path.
					relPath = cutPath
				} else {
					return api.OnLoadResult{}, nil
				}

				bytes, err := os.ReadFile(args.Path)
				if err != nil {
					return api.OnLoadResult{}, err
				}

				dir := filepath.Dir(relPath)
				prefix := fmt.Sprintf("const __filename = %q, __dirname = %q;\n", relPath, dir)
				contents := prefix + string(bytes)

				loader := api.LoaderJS
				switch filepath.Ext(args.Path) {
				case ".jsx":
					loader = api.LoaderJSX
				case ".ts":
					loader = api.LoaderTS
				case ".tsx":
					loader = api.LoaderTSX
				}

				return api.OnLoadResult{
					Contents:   &contents,
					ResolveDir: filepath.Dir(args.Path),
					Loader:     loader,
				}, nil
			})
	},
}
