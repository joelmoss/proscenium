package plugin

import (
	"fmt"
	"joelmoss/proscenium/internal/css"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path/filepath"
	"strings"

	esbuild "github.com/joelmoss/esbuild-internal/api"
	"github.com/joelmoss/esbuild-internal/ast"
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

				isCssModule := utils.PathIsCssModule(args.Path)

				// If stylesheet is imported from JS, then we return JS code that appends the stylesheet
				// contents in a <style> tag in the <head> of the page, and if the stylesheet is a CSS
				// module, it exports a plain object of class names.
				if pluginData.ImportedFromJs && isCssModule {
					urlPath := buildUrlPath(args.Path)
					cssResult := cssBuild(urlPath[1:])
					if len(cssResult.Errors) != 0 {
						return esbuild.OnLoadResult{
							Errors:   cssResult.Errors,
							Warnings: cssResult.Warnings,
						}, fmt.Errorf("%s", cssResult.Errors[0].Text)
					}

					if len(cssResult.OutputFiles) > 1 {
						return esbuild.OnLoadResult{}, fmt.Errorf("Multiple output files generated for %s", args.Path)
					}

					hash := ast.CssLocalHash(args.Path)
					hashIdent := hash
					if !build.InitialOptions.MinifyIdentifiers {
						relPath, _ := filepath.Rel(build.InitialOptions.AbsWorkingDir, args.Path)
						hashIdent = hashIdent + "_" + ast.CssLocalAppendice(relPath)
					}

					contents := strings.TrimSpace(string(cssResult.OutputFiles[0].Contents))
					contents = `
							const d = document;
							const u = '` + urlPath + `';
							const es = d.querySelector('#_` + hash + `');
							const el = d.querySelector('link[href="' + u + '"]');
							if (!es && !el) {
								const metaTag = d.querySelector('meta[name="csp-nonce"]');
								const nonce = metaTag?.content;
								const e = d.createElement('style');
								if (nonce) e.nonce = nonce;
								e.id = '_` + hash + `';
								e.dataset.href = u;
								e.dataset.prosceniumStyle = true;
								e.appendChild(d.createTextNode(` + fmt.Sprintf("String.raw`%s`", contents) + `));
								const ps = d.head.querySelector('[data-proscenium-style]');
								ps ? d.head.insertBefore(e, ps) : d.head.appendChild(e);
							}
							` + cssModulesProxyTemplate(hashIdent)

					debug.Debug("OnLoad:end", args)

					return esbuild.OnLoadResult{
						Contents:   &contents,
						ResolveDir: types.Config.RootPath,
						Loader:     esbuild.LoaderJS,
					}, nil
				}

				contents, warnings, err := css.ParseCssFile(args.Path)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				loader := esbuild.LoaderCSS
				if isCssModule {
					loader = esbuild.LoaderLocalCSS
				}

				return esbuild.OnLoadResult{
					Contents: &contents,
					Loader:   loader,
					Warnings: cssWarningsToMessages(warnings),
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

				contents, warnings, err := css.ParseCssFile(args.Path)
				if err != nil {
					return esbuild.OnLoadResult{}, err
				}

				loader := esbuild.LoaderCSS
				if utils.PathIsCssModule(args.Path) {
					loader = esbuild.LoaderLocalCSS
				}

				return esbuild.OnLoadResult{
					Contents: &contents,
					Loader:   loader,
					Warnings: cssWarningsToMessages(warnings),
				}, nil
			})
	},
}

func cssWarningsToMessages(warnings []css.CssWarning) []esbuild.Message {
	if len(warnings) == 0 {
		return nil
	}

	msgs := make([]esbuild.Message, len(warnings))
	for i, w := range warnings {
		msgs[i] = esbuild.Message{
			Text: w.Text,
			Location: &esbuild.Location{
				File:      w.FilePath,
				Namespace: "file",
				Line:      w.Line,
				Column:    w.Column,
				Length:    w.Length,
				LineText:  w.LineText,
			},
		}
	}
	return msgs
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
        return p in t || typeof p === 'symbol' ? Reflect.get(t, p, r) : p + '_` + hash + `';
      }
    });
	`
}

// Build the given `urlPath`
func cssBuild(urlPath string) esbuild.BuildResult {
	minify := !types.Config.InternalTesting && !types.Config.Debug && types.Config.Environment != types.DevEnv

	return esbuild.Build(esbuild.BuildOptions{
		EntryPoints:                 []string{urlPath},
		AbsWorkingDir:               types.Config.RootPath,
		LogLevel:                    esbuild.LogLevelSilent,
		LogLimit:                    1,
		Outdir:                      types.Config.OutputDir,
		Outbase:                     "./",
		MinifyWhitespace:            minify,
		MinifyIdentifiers:           minify,
		MinifySyntax:                minify,
		DeterministicLocalCSSNaming: true,
		Bundle:                      true,
		External:                    types.Config.External,
		Conditions:                  []string{types.Config.Environment.String(), "proscenium"},
		Write:                       false,
		Sourcemap:                   esbuild.SourceMapNone,
		LegalComments:               esbuild.LegalCommentsNone,
		Plugins:                     []esbuild.Plugin{Bundler, Svg, cssOnly},
		Target:                      esbuild.ES2022,
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
