package golib

import (
	"fmt"

	plugin "joelmoss/proscenium/golib/plugin"

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

// Build the given `path` in the `root`.
//
//	path - The path to build relative to `root`.
//	root - The working directory.
//	env  - The environment (1 = development, 2 = test, 3 = production)
//
//export build
func Build(path string, root string, env Environment, debug bool) api.BuildResult {
	minify := !debug && env != TestEnv

	logLevel := func() api.LogLevel {
		if debug {
			return api.LogLevelDebug
		} else {
			return api.LogLevelSilent
		}
	}

	result := api.Build(api.BuildOptions{
		EntryPoints:       []string{path},
		AbsWorkingDir:     root,
		LogLevel:          logLevel(),
		LogLimit:          1,
		Outdir:            "public/assets",
		Outbase:           "./",
		Format:            api.FormatESModule,
		JSX:               api.JSXAutomatic,
		JSXDev:            env != TestEnv && env != ProdEnv,
		MinifyWhitespace:  minify,
		MinifyIdentifiers: minify,
		MinifySyntax:      minify,
		Define:            map[string]string{"process.env.NODE_ENV": fmt.Sprintf("'%s'", env)},
		Bundle:            true,
		External:          []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"},
		KeepNames:         env != ProdEnv,
		Write:             false,
		// Sourcemap: isSourceMap ? 'external' : false,

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},

		Plugins: []api.Plugin{plugin.Svg, plugin.Resolve},
	})

	return result
}
