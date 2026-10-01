package builder

import (
	"encoding/json"
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

	// External emits the map as a second output file, which BuildToString then has to throw away
	// unless it was the map that was asked for - so getting both means building twice. Inline
	// hands back one file carrying both.
	sourcemap := esbuild.SourceMapExternal
	if cfg.SourcemapInline {
		sourcemap = esbuild.SourceMapInline
	}

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
		Sourcemap:                   sourcemap,
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

	buildOptions.Plugins = append(buildOptions.Plugins, plugin.Replacements(cfg), plugin.Svg(cfg), plugin.Css(cfg), plugin.Dirname(cfg))

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
	// RAILS_ENV and NODE_ENV are always defined: seeded from the environment first, then
	// overwritten by any given env vars. They used to be seeded only when no env vars were given at
	// all, so any configured env var without RAILS_ENV beside it left an empty define, which
	// esbuild rejects - failing the whole build.
	env := jsString(cfg.Environment.String())
	envVarMap := map[string]string{
		"proscenium.env.RAILS_ENV": env,
		"proscenium.env.NODE_ENV":  env,
	}

	for key, value := range cfg.EnvVars {
		if key != "" {
			envVarMap["proscenium.env."+key] = jsString(value)
		}
	}

	envVarMap["process.env.NODE_ENV"] = envVarMap["proscenium.env.RAILS_ENV"]
	envVarMap["proscenium.env"] = "undefined"

	return envVarMap
}

// A JS string literal for any value, which is what a define must be. JSON's string syntax is a
// subset of JS's. Wrapping the value in quotes unescaped, as this used to, failed every build on a
// value holding a quote or a newline, and decoded a backslash sequence such as `C:\new`.
func jsString(value string) string {
	b, _ := json.Marshal(value) // a string always marshals

	return string(b)
}
