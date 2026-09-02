package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/replacements"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

type compileResult struct {
	Errors   []esbuild.Message
	Warnings []esbuild.Message
}

func Compile(cfg *types.ConfigT) (bool, string) {
	// Check if Precompile is empty
	if len(cfg.Precompile) == 0 {
		return compileError(
			"No precompile paths specified",
			"The `precompile` configuration option must be an array, and specify at least one path or glob path to compile.",
		)
	}

	// Delete old compiled assets.
	os.RemoveAll(path.Join(cfg.RootPath, cfg.OutputDir))

	_, err := replacements.Build()
	if err != nil {
		return compileError("build npm replacements", err.Error())
	}

	minify := cfg.ShouldMinify()

	logLevel := esbuild.LogLevelInfo
	if cfg.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	buildOptions := esbuild.BuildOptions{
		EntryPoints:                 cfg.Precompile,
		Splitting:                   cfg.CodeSplitting,
		AbsWorkingDir:               cfg.RootPath,
		AbsPaths:                    esbuild.MetafileAbsPath,
		LogLevel:                    logLevel,
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
		Write:                       true,
		Sourcemap:                   esbuild.SourceMapLinked,
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

	definitions := buildEnvVars(cfg)
	buildOptions.Define = definitions
	buildOptions.Define["proscenium.env.PRECOMPILED"] = "true"
	buildOptions.Define["global"] = "window"

	result := esbuild.Build(buildOptions)

	messages, err := json.Marshal(compileResult{
		Errors:   result.Errors,
		Warnings: result.Warnings,
	})
	if err != nil {
		return false, string(err.Error())
	}

	if len(result.Errors) != 0 {
		return false, string(messages)
	}

	os.WriteFile(path.Join(cfg.RootPath, cfg.OutputDir, ".manifest.json"), []byte(result.Metafile), 0644)

	return true, string(messages)
}

func compileError(msg string, detail string) (bool, string) {
	errs := esbuild.BuildResult{
		Errors: []esbuild.Message{{
			Text:   msg,
			Detail: detail,
		}},
	}

	j, err := json.Marshal(errs)
	if err != nil {
		return false, string(err.Error())
	}

	return false, string(j)
}
