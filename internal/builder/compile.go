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

func Compile() (bool, string) {
	// Check if Precompile is empty
	if len(types.Config.Precompile) == 0 {
		return compileError(
			"No precompile paths specified",
			"The `precompile` configuration option must be an array, and specify at least one path or glob path to compile.",
		)
	}

	// Delete old compiled assets.
	os.RemoveAll(path.Join(types.Config.RootPath, types.Config.OutputDir))

	_, err := replacements.Build()
	if err != nil {
		return compileError("build npm replacements", err.Error())
	}

	minify := !types.Config.InternalTesting && !types.Config.Debug && types.Config.Environment != types.DevEnv

	logLevel := esbuild.LogLevelInfo
	if types.Config.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	buildOptions := esbuild.BuildOptions{
		EntryPoints:                 types.Config.Precompile,
		Splitting:                   types.Config.CodeSplitting,
		AbsWorkingDir:               types.Config.RootPath,
		AbsPaths:                    esbuild.MetafileAbsPath,
		LogLevel:                    logLevel,
		Outdir:                      types.Config.OutputDir,
		Outbase:                     "./",
		EntryNames:                  "[dir]/[name]-$[hash]$",
		AssetNames:                  "[dir]/[name]-$[hash]$",
		ChunkNames:                  "_asset_chunks/[name]-$[hash]$",
		Format:                      esbuild.FormatESModule,
		JSX:                         esbuild.JSXAutomatic,
		JSXDev:                      types.Config.Environment != types.TestEnv && types.Config.Environment != types.ProdEnv,
		MinifyWhitespace:            minify,
		MinifyIdentifiers:           minify,
		MinifySyntax:                minify,
		DeterministicLocalCSSNaming: true,
		Bundle:                      true,
		Conditions:                  []string{types.Config.Environment.String(), "proscenium"},
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
		plugin.I18n,
		plugin.Rjs(),
	}

	if types.Config.Bundle {
		buildOptions.External = types.Config.External
		buildOptions.Plugins = append(buildOptions.Plugins, plugin.Bundler)
	} else {
		buildOptions.PreserveSymlinks = true
		buildOptions.Plugins = append(buildOptions.Plugins, plugin.Bundless)
	}

	buildOptions.Plugins = append(buildOptions.Plugins, plugin.Replacements, plugin.Svg, plugin.Css, plugin.Dirname)

	definitions, err := buildEnvVars()
	if err != nil {
		return compileError("Failed to parse environment variables", err.Error())
	}

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

	os.WriteFile(path.Join(types.Config.RootPath, types.Config.OutputDir, ".manifest.json"), []byte(result.Metafile), 0644)

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
