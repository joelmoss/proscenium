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

// Build the given `path`.
//
// - path - The path to build relative to `root`. Multiple paths can be separated by a semicolon.
// - output - The output format. Defaults to `outputToString`. Can also be `outputToPath`.
//
//export build
func build(path string, outputToPath bool) esbuild.BuildResult {
	entrypoints := strings.Split(path, ";")

	// Ensure entrypoints are bare specifiers (do not begin with a `/`, `./` or `../`).
	for i, entrypoint := range entrypoints {
		if !utils.IsBareSpecifier(entrypoint) {
			return esbuild.BuildResult{
				Errors: []esbuild.Message{{
					Text:   fmt.Sprintf("Could not resolve %q", entrypoint),
					Detail: "Entrypoints must be bare specifiers",
				}},
			}
		}
		entrypoints[i] = entrypoint
	}

	_, err := importmap.Imports()
	if err != nil {
		return esbuild.BuildResult{
			Errors: []esbuild.Message{{
				Text:   "Failed to parse importmap",
				Detail: err.Error(),
			}},
		}
	}

	minify := !types.Config.Debug && types.Config.Environment == types.ProdEnv

	logLevel := esbuild.LogLevelSilent
	if types.Config.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	sourcemap := esbuild.SourceMapNone
	if outputToPath {
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
		Metafile:          outputToPath,
		Target:            esbuild.ES2022,

		// Ensure CSS modules are treated as plain CSS, and not esbuild's "local css".
		Loader: map[string]esbuild.Loader{
			".module.css": esbuild.LoaderCSS,
		},

		Supported: map[string]bool{
			// Ensure CSS nesting is transformed for browsers that don't support it.
			"nesting": false,
		},

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},
	}

	buildOptions.Plugins = []esbuild.Plugin{
		plugin.Http,
		plugin.I18n,
		plugin.Rjs(),
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

		if outputToPath {
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
