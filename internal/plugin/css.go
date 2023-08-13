package plugin

import (
	"fmt"
	"joelmoss/proscenium/internal/css"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

var Css = esbuild.Plugin{
	Name: "Css",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				// pp.Println("[6] filter(.css$)", args)

				var pluginData types.PluginData
				if args.PluginData != nil {
					pluginData = args.PluginData.(types.PluginData)
				}

				relativePath := strings.TrimPrefix(args.Path, root)

				hash := ""
				if pluginData.CssModuleHash != "" {
					hash = pluginData.CssModuleHash
				} else {
					hash = utils.ToDigest(relativePath)
				}

				// If stylesheet is imported from JS, then we return JS code that appends the stylesheet
				// contents in a <style> tag in the <head> of the page, and if the stylesheet is a CSS
				// module, it exports a plain object of class names.
				if pluginData.ImportedFromJs {
					cssResult := cssBuild(CssBuildOptions{
						Path: relativePath[1:],
						Root: root,
					})

					if len(cssResult.Errors) != 0 {
						return esbuild.OnLoadResult{
							Errors:   cssResult.Errors,
							Warnings: cssResult.Warnings,
						}, fmt.Errorf(cssResult.Errors[0].Text)
					}

					contents := strings.TrimSpace(string(cssResult.OutputFiles[0].Contents))
					contents = `
						const existingStyle = document.querySelector('#_` + hash + `');
						const existingLink = document.querySelector('link[href="` + relativePath + `"]');
						if (!existingStyle && !existingLink) {
							const e = document.createElement('style');
							e.id = '_` + hash + `';
							e.dataset.href = '` + relativePath + `';
							e.appendChild(document.createTextNode(` + fmt.Sprintf("`%s`", contents) + `));
							document.head.insertBefore(e, document.querySelector('style'));
						}
					`

					if utils.PathIsCssModule(args.Path) {
						contents = contents + cssModulesProxyTemplate(hash)
					}

					return esbuild.OnLoadResult{
						Contents:   &contents,
						ResolveDir: root,
						Loader:     esbuild.LoaderJS,
					}, nil
				}

				contents, err := css.ParseCssFile(args.Path, root, hash)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				return esbuild.OnLoadResult{
					Contents:   &contents,
					Loader:     esbuild.LoaderCSS,
					PluginData: types.PluginData{CssModuleHash: hash},
				}, nil
			})
	},
}

var cssOnly = esbuild.Plugin{
	Name: "cssOnly",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		// Parse CSS files.
		build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				// pp.Println("[cssOnly] filter(.css$)", args)

				var pluginData types.PluginData
				if args.PluginData != nil {
					pluginData = args.PluginData.(types.PluginData)
				}

				relativePath := strings.TrimPrefix(args.Path, root)

				hash := ""
				if pluginData.CssModuleHash != "" {
					hash = pluginData.CssModuleHash
				} else {
					hash = utils.ToDigest(relativePath)
				}

				contents, err := css.ParseCssFile(args.Path, root, hash)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				return esbuild.OnLoadResult{
					Contents:   &contents,
					Loader:     esbuild.LoaderCSS,
					PluginData: types.PluginData{CssModuleHash: hash},
				}, nil
			})
	},
}

func cssModulesProxyTemplate(hash string) string {
	return `
    export default new Proxy( {}, {
      get(target, prop, receiver) {
        if (prop in target || typeof prop === 'symbol') {
          return Reflect.get(target, prop, receiver);
        } else {
          return prop + '-` + hash + `';
        }
      }
    });
	`
}

type CssBuildOptions struct {
	Path  string // The path to build relative to `root`.
	Root  string
	Debug bool
}

// Build the given `path` in the `root`.
//
//export build
func cssBuild(options CssBuildOptions) esbuild.BuildResult {
	minify := !options.Debug && types.Config.Environment == types.ProdEnv

	logLevel := esbuild.LogLevelSilent
	if options.Debug {
		logLevel = esbuild.LogLevelDebug
	}

	return esbuild.Build(esbuild.BuildOptions{
		EntryPoints:       []string{options.Path},
		AbsWorkingDir:     options.Root,
		LogLevel:          logLevel,
		LogLimit:          1,
		Outdir:            "public/assets",
		Outbase:           "./",
		MinifyWhitespace:  minify,
		MinifyIdentifiers: minify,
		MinifySyntax:      minify,
		Bundle:            true,
		External:          []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"},
		Conditions:        []string{types.Config.Environment.String(), "proscenium"},
		Write:             false,
		Sourcemap:         esbuild.SourceMapNone,
		LegalComments:     esbuild.LegalCommentsNone,
		Plugins:           []esbuild.Plugin{Bundler, Svg, Url, cssOnly},
		Target:            esbuild.ES2022,
		Supported: map[string]bool{
			// Ensure CSS  esting is transformed for browsers that don't support it.
			"nesting": false,
		},

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},
	})
}
