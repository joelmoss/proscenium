package builder

import (
	"encoding/json"
	"fmt"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/replacements"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"os"
	"path/filepath"
	"strings"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

type compileResult struct {
	Errors   []esbuild.Message
	Warnings []esbuild.Message
}

// A panic anywhere below, on this goroutine, is returned as a failed compile rather than taking
// down the Ruby process that called in. See BuildToString.
func Compile(cfg *types.ConfigT) (success bool, messages string) {
	if perr := utils.Recover(func() {
		success, messages = compile(cfg)
	}); perr != nil {
		return compileError(perr.Text(), perr.Stack)
	}

	return success, messages
}

// The JSON a failed compile hands to Ruby, for the cgo export in main.go: the config it was given
// did not parse, so there is no build to report on, but Ruby still expects the messages shape.
func CompileErrorJSON(msg string, detail string) string {
	_, j := compileError(msg, detail)

	return j
}

func compile(cfg *types.ConfigT) (bool, string) {
	// Check if Precompile is empty
	if len(cfg.Precompile) == 0 {
		return compileError(
			"No precompile paths specified",
			"The `precompile` configuration option must be an array, and specify at least one path or glob path to compile.",
		)
	}

	// The delete below removes whatever OutputDir names, so it has to name a directory strictly
	// inside the root. Empty joins to the root itself (`Builder.compile(OutputDir: nil)` was enough
	// to delete the whole application), and `..` segments join to something above it:
	// OutputDirUnderRoot cleans them before RemoveAll sees the path.
	outputPath, ok := OutputDirUnderRoot(cfg)
	if !ok {
		return compileError(
			"Invalid output directory",
			fmt.Sprintf("The `output_dir` configuration option must name a directory inside the root, that compiled assets are written to. Got %q.", cfg.OutputDir),
		)
	}

	// Delete old compiled assets.
	os.RemoveAll(outputPath)

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

	buildOptions.Plugins = append(buildOptions.Plugins, plugin.Replacements(cfg), plugin.Svg(cfg), plugin.Css(cfg), plugin.Dirname(cfg))

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

	// Reported rather than ignored: without the manifest, Resolver hands back source paths instead
	// of the digest URLs under OutputDir, so a precompile that "succeeded" leaves the app serving
	// something other than what it just built.
	manifestPath := utils.JoinFsPath(cfg.RootPath, cfg.OutputDir, ".manifest.json")
	if err := os.WriteFile(manifestPath, []byte(result.Metafile), 0644); err != nil {
		return compileError("Failed to write the asset manifest", err.Error())
	}

	return true, string(messages)
}

// The path OutputDir names under the root, and whether it is strictly inside it: not the root
// itself, and not above or beside it. Compared as a relative path rather than by string prefix, so
// a root of "/" or "." is judged the same as any other.
//
// An absolute OutputDir is refused outright. filepath.Join would nest it under the root and pass
// this check, but esbuild's Outdir takes the raw value and would write where it points, outside
// the root; the manifest path joins it under the root as well. It is a path relative to the root.
// FsPathIsAbs rather than filepath.IsAbs, which answers false for "/public/assets" on Windows and
// let exactly the value this refuses through to esbuild.
//
// The comparison stays in filepath, which is the one package that knows where a drive root ends,
// and only the answer is converted - every path this hands back is used as a filesystem path by
// code that expects slash-form.
func OutputDirUnderRoot(cfg *types.ConfigT) (string, bool) {
	if utils.FsPathIsAbs(cfg.OutputDir) {
		return "", false
	}

	root := filepath.Clean(cfg.RootPath)
	target := filepath.Join(root, cfg.OutputDir)

	rel, err := filepath.Rel(root, target)
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return filepath.ToSlash(target), false
	}

	return filepath.ToSlash(target), true
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
