package plugin

import (
	"fmt"
	"joelmoss/proscenium/internal/css"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

var Css = esbuild.Plugin{
	Name: "Css",
	Setup: func(build esbuild.PluginBuild) {
		build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				debug.Debug("OnLoad:begin", args)

				var pluginData types.PluginData
				if args.PluginData != nil {
					pluginData = args.PluginData.(types.PluginData)
				}

				if args.Namespace == "rubygems" && pluginData.RealPath != "" {
					args.Path = pluginData.RealPath
				}

				urlPath := buildUrlPath(args.Path)
				hash := utils.ToDigest(urlPath)

				// If stylesheet is imported from JS, then we return JS code that appends the stylesheet
				// contents in a <style> tag in the <head> of the page, and if the stylesheet is a CSS
				// module, it exports a plain object of class names.
				if pluginData.ImportedFromJs {
					contents := ""

					if utils.PathIsCssModule(args.Path) && args.With["type"] == "cssmodulenames" {
						// User has requested only the CSS module names be returned.
						contents = cssModulesProxyTemplate(hash)
					} else {
						cssResult := cssBuild(urlPath[1:])

						if len(cssResult.Errors) != 0 {
							return esbuild.OnLoadResult{
								Errors:   cssResult.Errors,
								Warnings: cssResult.Warnings,
							}, fmt.Errorf("%s", cssResult.Errors[0].Text)
						}

						contents = strings.TrimSpace(string(cssResult.OutputFiles[0].Contents))
						contents = `
							const u = '` + urlPath + `';
							const es = document.querySelector('#_` + hash + `');
							const el = document.querySelector('link[href="' + u + '"]');
							if (!es && !el) {
								const e = document.createElement('style');
								e.id = '_` + hash + `';
								e.dataset.href = u;
								e.dataset.prosceniumStyle = true;
								e.appendChild(document.createTextNode(` + fmt.Sprintf("String.raw`%s`", contents) + `));
								const ps = document.head.querySelector('[data-proscenium-style]');
								ps ? document.head.insertBefore(e, ps) : document.head.appendChild(e);
							}
						`

						if utils.PathIsCssModule(args.Path) {
							contents = contents + cssModulesProxyTemplate(hash)
						}
					}

					return esbuild.OnLoadResult{
						Contents:   &contents,
						ResolveDir: types.Config.RootPath,
						Loader:     esbuild.LoaderJS,
					}, nil
				}

				contents, err := css.ParseCssFile(args.Path, hash)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				return esbuild.OnLoadResult{
					Contents: &contents,
					Loader:   esbuild.LoaderCSS,
				}, nil
			})
	},
}

var cssOnly = esbuild.Plugin{
	Name: "cssOnly",
	Setup: func(build esbuild.PluginBuild) {
		// Parse CSS files.
		build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				debug.Debug("cssOnly.OnLoad", args)

				hash := utils.ToDigest(buildUrlPath(args.Path))
				contents, err := css.ParseCssFile(args.Path, hash)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				return esbuild.OnLoadResult{
					Contents: &contents,
					Loader:   esbuild.LoaderCSS,
				}, nil
			})
	},
}

func buildUrlPath(path string) string {
	gemName, gemPath, found := utils.PathIsRubyGem(path)
	if found {
		return "/node_modules/" + types.RubyGemsScope + gemName + strings.TrimPrefix(path, gemPath)
	} else {
		return strings.TrimPrefix(path, types.Config.RootPath)
	}
}

func cssModulesProxyTemplate(hash string) string {
	return `
    export default new Proxy( {}, {
      get(t, p, r) {
        return p in t || typeof p === 'symbol' ? Reflect.get(t, p, r) : p + '-` + hash + `';
      }
    });
	`
}

// Build the given `urlPath`
func cssBuild(urlPath string) esbuild.BuildResult {
	minify := types.Config.Environment == types.ProdEnv

	return esbuild.Build(esbuild.BuildOptions{
		EntryPoints:       []string{urlPath},
		AbsWorkingDir:     types.Config.RootPath,
		LogLevel:          esbuild.LogLevelSilent,
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
		Plugins:           []esbuild.Plugin{Bundler(""), Svg, cssOnly},
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
