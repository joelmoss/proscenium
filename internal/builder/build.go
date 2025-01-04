package builder

import (
	"fmt"
	"strings"

	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type Output uint8

const (
	OutputToString Output = iota + 1
	OutputToPath
)

// Build the given `path` in the `config.RootPath`.
//
// - path - The path to build relative to `root`.
// - config
//   - RootPath - The working directory, usually Rails root.
//   - GemPath - Proscenium gem root.
//   - Environment - The environment (1 = development, 2 = test, 3 = production)
//   - EnvVars - Map of environment variables.
//   - Engines- Map of Rails engine names and paths.
//   - CodeSpitting?
//   - Bundle?
//   - Debug?
//
//export build
func Build(path string, args ...Output) esbuild.BuildResult {
	entrypoints := strings.Split(path, ";")

	_, err := importmap.Imports()
	if err != nil {
		return esbuild.BuildResult{
			Errors: []esbuild.Message{{
				Text:   "Failed to parse importmap",
				Detail: err.Error(),
			}},
		}
	}

	output := OutputToString
	if len(args) > 0 {
		output = args[0]
	}

	minify := !types.Config.Debug && types.Config.Environment == types.ProdEnv

	logLevel := esbuild.LogLevelSilent
	if types.Config.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	sourcemap := esbuild.SourceMapNone
	if output == OutputToPath {
		sourcemap = esbuild.SourceMapLinked
	} else if strings.HasSuffix(path, ".map") {
		path = strings.TrimSuffix(path, ".map")
		entrypoints = []string{path}
		sourcemap = esbuild.SourceMapExternal
	}

	buildOptions := esbuild.BuildOptions{
		EntryPoints:       entrypoints,
		Splitting:         types.Config.CodeSplitting,
		AbsWorkingDir:     types.Config.RootPath,
		LogLevel:          logLevel,
		LogLimit:          1,
		Outdir:            "public/assets",
		Outbase:           "./",
		ChunkNames:        "_asset_chunks/[name]-[hash]",
		Format:            esbuild.FormatESModule,
		JSX:               esbuild.JSXAutomatic,
		JSXDev:            types.Config.Environment != types.TestEnv && types.Config.Environment != types.ProdEnv,
		MinifyWhitespace:  minify,
		MinifyIdentifiers: minify,
		MinifySyntax:      minify,
		Bundle:            true,
		ResolveExtensions: []string{".tsx", ".ts", ".jsx", ".js", ".mjs", ".css", ".json"},
		Conditions:        []string{types.Config.Environment.String(), "proscenium"},
		Write:             true,
		Sourcemap:         sourcemap,
		LegalComments:     esbuild.LegalCommentsNone,
		Metafile:          output == OutputToPath,
		Target:            esbuild.ES2022,

		// Ensure CSS modules are treated as plain CSS, and not esbuild's "local css".
		Loader: map[string]esbuild.Loader{
			".module.css": esbuild.LoaderCSS,
		},

		Supported: map[string]bool{
			// Ensure CSS nesting is transformed for browsers that don't support it.
			"nesting": false,
		},

		// TODO: Will using aliases instead of import map be faster?
		// Alias: map[string]string{"foo/sdf.js": "./lib/foo.js"},

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},
	}

	buildOptions.Plugins = []esbuild.Plugin{
		plugin.I18n,
		plugin.Rjs(),
		plugin.Ui,
	}

	if types.Config.Bundle {
		buildOptions.External = []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"}
		buildOptions.Plugins = append(buildOptions.Plugins, plugin.Bundler)
	} else {
		buildOptions.Plugins = append(buildOptions.Plugins, plugin.Bundless)
	}

	buildOptions.Plugins = append(buildOptions.Plugins, plugin.Svg, plugin.Css)

	if !utils.IsUrl(path) {
		definitions, err := buildEnvVars()
		if err != nil {
			return esbuild.BuildResult{
				Errors: []esbuild.Message{{
					Text:   "Failed to parse environment variables",
					Detail: err.Error(),
				}},
			}
		}
		buildOptions.Define = definitions
		buildOptions.Define["global"] = "window"

		if output == OutputToPath {
			buildOptions.EntryNames = "[dir]/[name]$[hash]$"
		}
	}

	return esbuild.Build(buildOptions)
}

// Maintains a cache of environment variables.
var envVarMap = make(map[string]string, 4)

func buildEnvVars() (map[string]string, error) {
	if types.Config.Environment != types.TestEnv && len(envVarMap) > 0 {
		return envVarMap, nil
	}

	for key, value := range types.Config.EnvVars {
		if key != "" || value != "" {
			envVarMap["proscenium.env."+key] = fmt.Sprintf("'%s'", value)
		}
	}

	if len(types.Config.EnvVars) == 0 {
		// This ensures that we always have NODE_ENV and RAILS_ENV defined even the given env vars do
		// not define them.
		env := fmt.Sprintf("'%s'", types.Config.Environment)
		envVarMap["proscenium.env.RAILS_ENV"] = env
		envVarMap["proscenium.env.NODE_ENV"] = env
	}

	envVarMap["process.env.NODE_ENV"] = envVarMap["proscenium.env.RAILS_ENV"]
	envVarMap["proscenium.env"] = "undefined"

	return envVarMap, nil
}
