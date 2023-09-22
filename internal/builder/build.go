package builder

import (
	"encoding/json"
	"fmt"
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

	// Base URL of the Rails app. eg. https://example.com
	BaseUrl string

	// Path to an import map (js or json), relative to the given root.
	ImportMapPath string

	// Environment variables as a JSON string.
	EnvVars string

	// Import map contents.
	ImportMap []byte
}

// Build the given `options.Path` in the `options.Root`.
//
//export build
func Build(options BuildOptions) esbuild.BuildResult {
	entrypoints := strings.Split(options.Path, ";")
	hasMultipleEntrypoints := len(entrypoints) > 1

	err := importmap.Parse(options.ImportMap, options.ImportMapPath)
	if err != nil {
		return esbuild.BuildResult{
			Errors: []esbuild.Message{{
				Text:   "Failed to parse import map",
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
	if hasMultipleEntrypoints {
		sourcemap = esbuild.SourceMapLinked
	} else if strings.HasSuffix(options.Path, ".map") {
		options.Path = strings.TrimSuffix(options.Path, ".map")
		entrypoints = []string{options.Path}
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
		External:          []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"},
		Conditions:        []string{types.Config.Environment.String(), "proscenium"},
		Write:             types.Config.CodeSplitting,
		Sourcemap:         sourcemap,
		LegalComments:     esbuild.LegalCommentsNone,
		Metafile:          hasMultipleEntrypoints,
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
		plugin.Libs,
		plugin.Rjs(options.BaseUrl),
		plugin.Bundler,
		plugin.Svg, plugin.Url, plugin.Css,
	}

	if utils.IsUrl(options.Path) || utils.IsEncodedUrl(options.Path) {
		buildOptions.Define = make(map[string]string, 2)
		buildOptions.Define["process.env.NODE_ENV"] = fmt.Sprintf("'%s'", types.Config.Environment.String())
		buildOptions.Define["proscenium.env"] = "undefined"
	} else {
		definitions, err := buildEnvVars(options.EnvVars)
		if err != nil {
			return esbuild.BuildResult{
				Errors: []esbuild.Message{{
					Text:   "Failed to parse environment variables",
					Detail: err.Error(),
				}},
			}
		}
		buildOptions.Define = definitions

		if hasMultipleEntrypoints {
			buildOptions.EntryNames = "[dir]/[name]$[hash]$"
		}
	}

	buildOptions.Define["global"] = "window"

	return esbuild.Build(buildOptions)
}

// Maintains a cache of environment variables.
var envVarMap = make(map[string]string, 4)

func buildEnvVars(envVarsS string) (map[string]string, error) {
	if types.Config.Environment != types.TestEnv && len(envVarMap) > 0 {
		return envVarMap, nil
	}

	if envVarsS != "" {
		var varsJson map[string]string
		err := json.Unmarshal([]byte(envVarsS), &varsJson)
		if err != nil {
			return nil, err
		}

		for key, value := range varsJson {
			if key != "" || value != "" {
				envVarMap["proscenium.env."+key] = fmt.Sprintf("'%s'", value)
			}
		}
	} else {
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
