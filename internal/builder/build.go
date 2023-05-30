package builder

import (
	"fmt"
	"os"
	"path"
	"strings"

	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/types"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type BuildOptions struct {
	// The path to build relative to `root`.
	Path string

	// The working directory. Usually the Rails root.
	Root string

	// Base URL of the Rails app. eg. https://example.com
	BaseUrl string

	// Path to an import map (js or json), relative to the given root.
	ImportMapPath string

	// Import map contents.
	ImportMap []byte

	Debug    bool
	Metafile bool
}

// Build the given `path` in the `root`.
//
//export build
func Build(options BuildOptions) esbuild.BuildResult {
	os.Setenv("RAILS_ENV", types.Env.String())

	isSourceMap := strings.HasSuffix(options.Path, ".map")

	err := importmap.Parse(options.ImportMap, options.ImportMapPath, options.Root)
	if err != nil {
		return esbuild.BuildResult{
			Errors: []esbuild.Message{{
				Text:   "Failed to parse import map",
				Detail: err.Error(),
			}},
		}
	}

	minify := !options.Debug && types.Env == types.ProdEnv

	logLevel := esbuild.LogLevelSilent
	if options.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	sourcemap := esbuild.SourceMapNone
	if isSourceMap {
		options.Path = strings.TrimSuffix(options.Path, ".map")
		sourcemap = esbuild.SourceMapExternal
	}

	plugins := []esbuild.Plugin{
		plugin.I18n,
		plugin.Env,
		plugin.Rjs(options.BaseUrl),
		plugin.Bundler,
	}
	plugins = append(plugins, plugin.Svg)
	plugins = append(plugins, plugin.Url)
	plugins = append(plugins, plugin.Css)

	result := esbuild.Build(esbuild.BuildOptions{
		EntryPoints:       []string{options.Path},
		AbsWorkingDir:     options.Root,
		LogLevel:          logLevel,
		LogLimit:          1,
		Outdir:            "public/assets",
		Outbase:           "./",
		Format:            esbuild.FormatESModule,
		JSX:               esbuild.JSXAutomatic,
		JSXDev:            types.Env != types.TestEnv && types.Env != types.ProdEnv,
		MinifyWhitespace:  minify,
		MinifyIdentifiers: minify,
		MinifySyntax:      minify,
		Define:            map[string]string{"process.env.NODE_ENV": fmt.Sprintf("'%s'", types.Env)},
		Bundle:            true,
		External:          []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"},
		// KeepNames:         types.Env != types.ProdEnv,
		Conditions:    []string{types.Env.String()},
		Write:         false,
		Sourcemap:     sourcemap,
		LegalComments: esbuild.LegalCommentsNone,
		Metafile:      options.Metafile,
		Plugins:       plugins,
		Target:        esbuild.ES2022,
		Supported:     map[string]bool{
			// Ensure CSS nesting is transformed for browsers that don't support it.
			// "nesting": false,
		},

		// TODO: Will using aliases instead of import be faster?
		// Alias: map[string]string{"foo/sdf.js": "./lib/foo.js"},

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},
	})

	if options.Metafile {
		os.WriteFile(path.Join(options.Root, "meta.json"), []byte(result.Metafile), 0644)
	}

	return result
}
