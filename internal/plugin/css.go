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

func Css(cfg *types.ConfigT) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "Css",
		Setup: func(build esbuild.PluginBuild) {
			build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
				func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
					// The first door: esbuild hands back the path in OS form. It is converted
					// before anything reads it, because ast.CssLocalHash below is fed this exact
					// string and Ruby mirrors that hash from a slash-form path.
					args.Path = filepath.ToSlash(args.Path)

					debug.Debug(cfg.Debug, "OnLoad:begin", args)

					pluginData := types.PluginDataOf(args.PluginData)

					if args.Namespace == "rubygems" && pluginData.RealPath != "" {
						args.Path = filepath.ToSlash(pluginData.RealPath)
					}

					isCssModule := utils.PathIsCssModule(args.Path)

					// If stylesheet is imported from JS, then we return JS code that appends the stylesheet
					// contents in a <style> tag in the <head> of the page, and if the stylesheet is a CSS
					// module, it exports a plain object of class names.
					if pluginData.ImportedFromJs && isCssModule {
						// A file under neither root used to fall through with its file system
						// path, and the build below then looked for that under the app root.
						// The error names the file, not its path: esbuild's location already
						// says who imported it, and the path is a machine path (see 6e046d87).
						urlPath, ok := utils.UrlPathFromFsPath(args.Path, cfg)
						if !ok {
							return esbuild.OnLoadResult{}, fmt.Errorf("%s is outside the app root and every bundled gem", filepath.Base(args.Path))
						}

						cssResult := cssBuild(urlPath[1:], cfg)
						if len(cssResult.Errors) != 0 {
							// The messages alone, with no error beside them. esbuild handles a returned
							// error first and drops the structured messages, so the failure used to point
							// at the JS importer rather than the CSS line, and any note (a recovered
							// panic's stack) was lost. Non-empty Errors fail the build on their own.
							return esbuild.OnLoadResult{
								Errors:   cssResult.Errors,
								Warnings: cssResult.Warnings,
							}, nil
						}

						if len(cssResult.OutputFiles) != 1 {
							return esbuild.OnLoadResult{}, fmt.Errorf("expected one output file for %s, got %d", args.Path, len(cssResult.OutputFiles))
						}

						hash := ast.CssLocalHash(args.Path)
						hashIdent := hash
						if !build.InitialOptions.MinifyIdentifiers {
							// Proscenium::Utils.css_module_suffix (lib/proscenium/utils.rb) mirrors this in
							// Ruby, for the class names a view emits. Change them together;
							// test/css_module/suffix_test.rb checks that they agree.
							//
							// Slash-form, because Ruby builds its half from a slash-form path and the fork
							// folds separators only in Windows absolute paths. A path on another drive
							// than the app has no relative form, and falls back to itself: that is what
							// esbuild's MakePrettyPaths does for the stylesheet's own class names.
							relPath, err := filepath.Rel(build.InitialOptions.AbsWorkingDir, args.Path)
							if err != nil {
								relPath = args.Path
							}
							hashIdent = hashIdent + "_" + ast.CssLocalAppendice(filepath.ToSlash(relPath))
						}

						contents := strings.TrimSpace(string(cssResult.OutputFiles[0].Contents))
						// The <style> injection is guarded on `document` existing. The exported class-name
						// Proxy is what a DOM-less runtime (a JS test runner, or SSR) actually wants, and
						// an unguarded `document` reference would throw before it could get it.
						contents = `
								if (typeof document !== 'undefined') {
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
								}
								` + cssModulesProxyTemplate(hashIdent)

						debug.Debug(cfg.Debug, "OnLoad:end", args)

						return esbuild.OnLoadResult{
							Contents:   &contents,
							ResolveDir: cfg.RootPath,
							Loader:     esbuild.LoaderJS,
						}, nil
					}

					contents, warnings, err := css.ParseCssFile(args.Path, cfg)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					loader := esbuild.LoaderCSS
					if isCssModule {
						loader = esbuild.LoaderLocalCSS
					}

					result := esbuild.OnLoadResult{
						Contents:   &contents,
						Loader:     loader,
						Warnings:   cssWarningsToMessages(warnings),
						ResolveDir: filepath.ToSlash(filepath.Dir(args.Path)),
					}

					// A gem stylesheet's imports resolve from the gem. bundless's OnLoad attaches the gem
					// root but returns no contents for CSS, and esbuild drops a loader result that has no
					// contents, so this is the only place the root can be carried. Without it, and
					// without the ResolveDir above (esbuild only defaults it for the file namespace),
					// every @import in gem CSS arrived with an empty ResolveDir and nil plugin data.
					if args.Namespace == "rubygems" {
						result.PluginData = types.PluginData{GemPath: pluginData.GemPath}
					}

					return result, nil
				})
		},
	}
}

func cssOnly(cfg *types.ConfigT) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "cssOnly",
		Setup: func(build esbuild.PluginBuild) {
			// Parse CSS files.
			build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
				func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
					args.Path = filepath.ToSlash(args.Path)

					debug.Debug(cfg.Debug, "cssOnly.OnLoad", args)

					contents, warnings, err := css.ParseCssFile(args.Path, cfg)
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
func cssBuild(urlPath string, cfg *types.ConfigT) esbuild.BuildResult {
	minify := cfg.ShouldMinify()

	return esbuild.Build(esbuild.BuildOptions{
		EntryPoints:                 []string{urlPath},
		AbsWorkingDir:               cfg.RootPath,
		LogLevel:                    esbuild.LogLevelSilent,
		LogLimit:                    1,
		Outdir:                      cfg.OutputDir,
		Outbase:                     "./",
		MinifyWhitespace:            minify,
		MinifyIdentifiers:           minify,
		MinifySyntax:                minify,
		DeterministicLocalCSSNaming: true,
		Bundle:                      true,
		External:                    cfg.External,
		Conditions:                  []string{cfg.Environment.String(), "proscenium"},
		Write:                       false,
		Sourcemap:                   esbuild.SourceMapNone,
		LegalComments:               esbuild.LegalCommentsNone,
		Plugins:                     []esbuild.Plugin{Bundler(cfg), Svg(cfg), cssOnly(cfg)},
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
