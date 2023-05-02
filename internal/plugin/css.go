package plugin

import (
	"joelmoss/proscenium/internal/css"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"regexp"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
	"github.com/k0kubun/pp/v3"
)

var Css = esbuild.Plugin{
	Name: "Css",
	Setup: func(build esbuild.PluginBuild) {
		root := build.InitialOptions.AbsWorkingDir

		// Parse CSS files.
		build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
			func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
				pp.Println("[6] filter(.css$)", args)

				relativePath := strings.TrimPrefix(args.Path, root)
				hash := utils.ToDigest(relativePath)

				importedFromJs := args.PluginData != nil && args.PluginData.(types.PluginData).ImportedFromJs

				// If stylesheet is imported from JS, then we return JS code that appends the stylesheet
				// in a <link> tag in the <head> of the page, and if the stylesheet is a CSS module, it
				// exports a plain object of class names.
				if importedFromJs {
					contents := `
						let e = document.querySelector('#_` + hash + `');
						if (!e) {
							e = document.createElement('link');
							e.id = '_` + hash + `';
							e.rel = 'stylesheet';
							e.href = '` + strings.TrimPrefix(args.Path, root) + `';
							document.head.appendChild(e);
						}
					`

					if pathIsCssModule(args.Path) {
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
					Contents: &contents,
					Loader:   esbuild.LoaderCSS,
				}, nil
			})
	},
}

func pathIsCssModule(path string) bool {
	var re = regexp.MustCompile(`\.module\.css$`)
	return re.MatchString(path)
}

func cssModulesProxyTemplate(hash string) string {
	return `
    export default new Proxy( {}, {
      get(target, prop, receiver) {
        if (prop in target || typeof prop === 'symbol') {
          return Reflect.get(target, prop, receiver);
        } else {
          return prop + '` + hash + `';
        }
      }
    });
	`
}
