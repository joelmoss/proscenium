package golib

import (
	"fmt"
	"path"

	"joelmoss/proscenium/golib/importmap"
	"joelmoss/proscenium/golib/plugin"

	"github.com/evanw/esbuild/pkg/api"
)

type Environment uint8

const (
	DevEnv Environment = iota + 1
	TestEnv
	ProdEnv
)

func (e Environment) String() string {
	return [...]string{"development", "test", "production"}[e-1]
}

type BuildOptions struct {
	Path          string
	Root          string
	Env           Environment
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
func Build(options BuildOptions) api.BuildResult {
	minify := !options.Debug && options.Env != TestEnv

	logLevel := func() api.LogLevel {
		if options.Debug {
			return api.LogLevelDebug
		} else {
			return api.LogLevelSilent
		}
	}

	pluginOpts := plugin.PluginOptions{}
	if len(options.ImportMap) > 0 {
		imap, err := importmap.Parse(options.ImportMap)
		if err != nil {
			return api.BuildResult{
				Errors: []api.Message{{Text: err.Error()}},
			}
		}

		pluginOpts.ImportMap = imap
	}
	if len(options.ImportMapPath) > 0 {
		imap, err := importmap.ParseFile(path.Join(options.Root, options.ImportMapPath))
		if err != nil {
			return api.BuildResult{
				Errors: []api.Message{{Text: err.Error()}},
			}
		}

		pluginOpts.ImportMap = imap
	}

	result := api.Build(api.BuildOptions{
		EntryPoints:       []string{options.Path},
		AbsWorkingDir:     options.Root,
		LogLevel:          logLevel(),
		LogLimit:          1,
		Outdir:            "public/assets",
		Outbase:           "./",
		Format:            api.FormatESModule,
		JSX:               api.JSXAutomatic,
		JSXDev:            options.Env != TestEnv && options.Env != ProdEnv,
		MinifyWhitespace:  minify,
		MinifyIdentifiers: minify,
		MinifySyntax:      minify,
		Define:            map[string]string{"process.env.NODE_ENV": fmt.Sprintf("'%s'", options.Env)},
		Bundle:            true,
		External:          []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"},
		KeepNames:         options.Env != ProdEnv,
		Write:             false,
		// Sourcemap: isSourceMap ? 'external' : false,

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},

		Plugins: []api.Plugin{
			// plugin.ImportMap(pluginOpts),
			plugin.Svg,
			plugin.Url,
			plugin.Resolve(pluginOpts),
		},
	})

	return result
}
