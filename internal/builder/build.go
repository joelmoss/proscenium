package builder

import (
	"fmt"
	"os"
	"path"

	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/types"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type BuildOptions struct {
	Path          string
	Root          string
	Env           types.Environment
	ImportMapPath string
	ImportMap     []byte
	Debug         bool
}

// Build the given `path` in the `root`.
//
//	path - The path to build relative to `root`.
//	root - The working directory.
//	env - The environment (1 = development, 2 = test, 3 = production)
//	importMap - Path to an import map (js or json), relative to the given root.
//
//export build
func Build(options BuildOptions) esbuild.BuildResult {
	os.Setenv("RAILS_ENV", options.Env.String())

	minify := !options.Debug && options.Env != types.TestEnv

	logLevel := func() esbuild.LogLevel {
		if options.Debug {
			return esbuild.LogLevelDebug
		} else {
			return esbuild.LogLevelSilent
		}
	}

	pluginOpts := types.PluginOptions{}
	if len(options.ImportMap) > 0 {
		imap, err := importmap.Parse(options.ImportMap, importmap.JsonType, options.Env)
		if err != nil {
			return esbuild.BuildResult{
				Errors: []esbuild.Message{{Text: err.Error()}},
			}
		}

		pluginOpts.ImportMap = imap
	}
	if len(options.ImportMapPath) > 0 {
		imap, err := importmap.ParseFile(path.Join(options.Root, options.ImportMapPath), options.Env)
		if err != nil {
			return esbuild.BuildResult{
				Errors: []esbuild.Message{{Text: err.Error()}},
			}
		}

		pluginOpts.ImportMap = imap
	}

	result := esbuild.Build(esbuild.BuildOptions{
		EntryPoints:       []string{options.Path},
		AbsWorkingDir:     options.Root,
		LogLevel:          logLevel(),
		LogLimit:          1,
		Outdir:            "public/assets",
		Outbase:           "./",
		Format:            esbuild.FormatESModule,
		JSX:               esbuild.JSXAutomatic,
		JSXDev:            options.Env != types.TestEnv && options.Env != types.ProdEnv,
		MinifyWhitespace:  minify,
		MinifyIdentifiers: minify,
		MinifySyntax:      minify,
		Define:            map[string]string{"process.env.NODE_ENV": fmt.Sprintf("'%s'", options.Env)},
		Bundle:            true,
		External:          []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"},
		KeepNames:         options.Env != types.ProdEnv,
		Conditions:        []string{options.Env.String()},
		Write:             false,
		// Sourcemap: isSourceMap ? 'external' : false,

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},

		Plugins: []esbuild.Plugin{
			// plugin.ImportMap(pluginOpts),
			plugin.Env,
			plugin.Svg,
			plugin.Css(),
			// plugin.Url,
			plugin.Resolve(pluginOpts),
		},
	})

	return result
}
