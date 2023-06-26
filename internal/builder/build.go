package builder

import (
	"fmt"
	"os"
	"path"
	"strings"

	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type BuildOptions struct {
	// The path to build relative to `root`. Multiple paths can be given by separating them with a
	// semi-colon.
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
	os.Setenv("NODE_ENV", types.Env.String())

	entrypoints := strings.Split(options.Path, ";")
	hasMultipleEntrypoints := len(entrypoints) > 1

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
	if hasMultipleEntrypoints {
		sourcemap = esbuild.SourceMapLinked
	} else if strings.HasSuffix(options.Path, ".map") {
		options.Path = strings.TrimSuffix(options.Path, ".map")
		entrypoints = []string{options.Path}
		sourcemap = esbuild.SourceMapExternal
	}

	buildOptions := esbuild.BuildOptions{
		EntryPoints:       entrypoints,
		Splitting:         hasMultipleEntrypoints,
		AbsWorkingDir:     options.Root,
		LogLevel:          logLevel,
		LogLimit:          1,
		Outdir:            "public/assets",
		Outbase:           "./",
		ChunkNames:        "_chunks/[name]-[hash]",
		Format:            esbuild.FormatESModule,
		JSX:               esbuild.JSXAutomatic,
		JSXDev:            types.Env != types.TestEnv && types.Env != types.ProdEnv,
		MinifyWhitespace:  minify,
		MinifyIdentifiers: minify,
		MinifySyntax:      minify,
		Bundle:            true,
		External:          []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"},
		Conditions:        []string{types.Env.String(), "proscenium"},
		Write:             hasMultipleEntrypoints,
		Sourcemap:         sourcemap,
		LegalComments:     esbuild.LegalCommentsNone,
		Metafile:          options.Metafile,
		Target:            esbuild.ES2022,
		Supported: map[string]bool{
			// Ensure CSS nesting is transformed for browsers that don't support it.
			"nesting": false,
		},

		// TODO: Will using aliases instead of import be faster?
		// Alias: map[string]string{"foo/sdf.js": "./lib/foo.js"},

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},
	}

	plugins := []esbuild.Plugin{
		plugin.I18n,
		plugin.Rjs(options.BaseUrl),
		plugin.Bundler,
	}
	plugins = append(plugins, plugin.Svg)
	plugins = append(plugins, plugin.Url)
	plugins = append(plugins, plugin.Css)
	buildOptions.Plugins = plugins

	if hasMultipleEntrypoints {
		buildOptions.EntryNames = "[dir]/[name]$[hash]$"
		buildOptions.Define = envVars()
	} else if utils.IsUrl(options.Path) || utils.IsEncodedUrl(options.Path) {
		buildOptions.Define = make(map[string]string, 2)
		buildOptions.Define["process.env.NODE_ENV"] = fmt.Sprintf("'%s'", types.Env.String())
		buildOptions.Define["proscenium.env"] = "undefined"
	} else {
		// TODO: Passing all env vars to Define is slow. We should only pass the ones that are needed by
		// requiring that they are declared first - perhaps as part of configuration.
		buildOptions.Define = envVars()
	}

	result := esbuild.Build(buildOptions)

	if options.Metafile {
		os.WriteFile(path.Join(options.Root, "meta.json"), []byte(result.Metafile), 0644)
	}

	return result
}

// Maintains a cache of environment variables.
var envVarMap = make(map[string]string, 2)

func envVars() map[string]string {
	if len(envVarMap) > 0 {
		return envVarMap
	}

	varStrings := os.Environ()
	for _, e := range varStrings {
		pair := strings.SplitN(e, "=", 2)

		if len(pair) == 1 {
			continue
		}

		envVarMap["proscenium.env."+pair[0]] = fmt.Sprintf("'%s'", pair[1])

		if pair[0] == "NODE_ENV" {
			envVarMap["process.env.NODE_ENV"] = fmt.Sprintf("'%s'", pair[1])
		}
	}

	envVarMap["proscenium.env"] = "undefined"

	return envVarMap
}
