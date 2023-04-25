package builder

import (
	"fmt"
	"os"
	"strings"

	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/types"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type BuildOptions struct {
	// The path to build relative to `root`.
	Path string

	// The working directory.
	Root string

	// The environment (1 = development, 2 = test, 3 = production)
	Env types.Environment

	// Path to an import map (js or json), relative to the given root.
	ImportMapPath string

	// Import map as a string.
	ImportMap []byte

	Debug bool
}

// Build the given `path` in the `root`.
//
//export build
func Build(options BuildOptions) esbuild.BuildResult {
	os.Setenv("RAILS_ENV", options.Env.String())

	isSourceMap := strings.HasSuffix(options.Path, ".map")
	pluginOpts := types.PluginOptions{Env: options.Env}

	imap, err := importmap.Parse(options.ImportMap, options.ImportMapPath, options.Root, options.Env)
	if err == nil {
		pluginOpts.ImportMap = imap
	} else {
		return esbuild.BuildResult{
			Errors: []esbuild.Message{{
				Text:   "Failed to parse import map",
				Detail: err.Error(),
			}},
		}
	}

	minify := !options.Debug && options.Env != types.TestEnv

	logLevel := esbuild.LogLevelSilent
	if options.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	sourcemap := esbuild.SourceMapNone
	if isSourceMap {
		options.Path = strings.TrimSuffix(options.Path, ".map")
		sourcemap = esbuild.SourceMapExternal
	}

	result := esbuild.Build(esbuild.BuildOptions{
		EntryPoints:       []string{options.Path},
		AbsWorkingDir:     options.Root,
		LogLevel:          logLevel,
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
		Sourcemap:         sourcemap,

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},

		Plugins: []esbuild.Plugin{
			plugin.Env,
			mainPlugin(pluginOpts),
			plugin.Svg,
		},
	})

	return result
}
