package builder

import (
	"fmt"
	"strings"

	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/replacements"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

// Build the given `path`.
//
// - path - The path to build relative to `root`.
//
//export build
func build(entryPoint string, cfg *types.ConfigT) esbuild.BuildResult {
	_, err := replacements.Build()
	if err != nil {
		return esbuild.BuildResult{
			Errors: []esbuild.Message{{
				Text:   "build npm replacements",
				Detail: err.Error(),
			}},
		}
	}

	// Ensure entrypoint is a bare specifier (does not begin with a `/`, `./` or `../`).
	if !utils.IsBareSpecifier(entryPoint) {
		return esbuild.BuildResult{
			Errors: []esbuild.Message{{
				Text:   fmt.Sprintf("Could not resolve %q", entryPoint),
				Detail: "Entrypoints must be bare specifiers",
			}},
		}
	}

	minify := cfg.ShouldMinify()

	logLevel := esbuild.LogLevelWarning
	if cfg.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	entryPoint = strings.TrimSuffix(entryPoint, ".map")

	buildOptions := esbuild.BuildOptions{
		EntryPoints:                 []string{entryPoint},
		Splitting:                   cfg.CodeSplitting,
		AbsWorkingDir:               cfg.RootPath,
		LogLevel:                    logLevel,
		LogLimit:                    1,
		Outdir:                      cfg.OutputDir,
		Outbase:                     "./",
		EntryNames:                  "[dir]/[name]-$[hash]$",
		AssetNames:                  "[dir]/[name]-$[hash]$",
		ChunkNames:                  "_asset_chunks/[name]-$[hash]$",
		Format:                      esbuild.FormatESModule,
		JSX:                         esbuild.JSXAutomatic,
		JSXDev:                      cfg.Environment != types.TestEnv && cfg.Environment != types.ProdEnv,
		MinifyWhitespace:            minify,
		MinifyIdentifiers:           minify,
		MinifySyntax:                minify,
		DeterministicLocalCSSNaming: true,
		Bundle:                      true,
		Conditions:                  []string{cfg.Environment.String(), "proscenium"},
		Write:                       cfg.ShouldWrite(),
		Sourcemap:                   esbuild.SourceMapExternal,
		LegalComments:               esbuild.LegalCommentsNone,
		Target:                      esbuild.ES2022,
		Metafile:                    true,

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
		plugin.I18n(cfg),
		plugin.Rjs(),
	}

	if cfg.Bundle {
		buildOptions.External = cfg.External
		buildOptions.Plugins = append(buildOptions.Plugins, plugin.Bundler(cfg))
	} else {
		buildOptions.PreserveSymlinks = true
		buildOptions.Plugins = append(buildOptions.Plugins, plugin.Bundless(cfg))
	}

	buildOptions.Plugins = append(buildOptions.Plugins, plugin.Replacements(cfg), plugin.Svg, plugin.Css(cfg), plugin.Dirname(cfg))

	if !utils.IsUrl(entryPoint) {
		definitions := buildEnvVars(cfg)
		buildOptions.Define = definitions
		buildOptions.Define["proscenium.env.PRECOMPILED"] = "false"
		buildOptions.Define["global"] = "window"
	}

	return esbuild.Build(buildOptions)
}

// Builds the map of environment variable defines. Recomputed on every call rather than cached -
// cheap (a handful of string entries) and avoids the unsynchronised global cache that used to
// live here.
func buildEnvVars(cfg *types.ConfigT) map[string]string {
	envVarMap := make(map[string]string, 4)

	for key, value := range cfg.EnvVars {
		if key != "" || value != "" {
			envVarMap["proscenium.env."+key] = fmt.Sprintf("'%s'", value)
		}
	}

	if len(cfg.EnvVars) == 0 {
		// This ensures that we always have NODE_ENV and RAILS_ENV defined even the given env vars do
		// not define them.
		env := fmt.Sprintf("'%s'", cfg.Environment)
		envVarMap["proscenium.env.RAILS_ENV"] = env
		envVarMap["proscenium.env.NODE_ENV"] = env
	}

	envVarMap["process.env.NODE_ENV"] = envVarMap["proscenium.env.RAILS_ENV"]
	envVarMap["proscenium.env"] = "undefined"

	return envVarMap
}
