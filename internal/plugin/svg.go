package plugin

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/evanw/esbuild/pkg/api"
)

// When importing an svg image from a jsx module, the svg is exported as a react component. It is
// assumed that the SVG file is located in /public.
var Svg = api.Plugin{
	Name: "svg",
	Setup: func(build api.PluginBuild) {
		var publicPath = filepath.Join(build.InitialOptions.AbsWorkingDir, "public")

		build.OnResolve(api.OnResolveOptions{Filter: `\.svg$`},
			func(args api.OnResolveArgs) (api.OnResolveResult, error) {
				if args.Kind == api.ResolveJSImportStatement && strings.HasSuffix(args.Importer, ".jsx") {
					return api.OnResolveResult{
						Path:      filepath.Join(publicPath, args.Path),
						Namespace: "svg",
					}, nil
				} else {
					return api.OnResolveResult{
						Path:     args.Path,
						External: true,
					}, nil
				}
			})

		build.OnLoad(api.OnLoadOptions{Filter: `.*`, Namespace: "svg"},
			func(args api.OnLoadArgs) (api.OnLoadResult, error) {
				bytes, err := os.ReadFile(args.Path)
				if err != nil {
					return api.OnLoadResult{}, err
				}

				contents := fmt.Sprintf(`
            import { cloneElement, Children } from 'react';
            const svg = %s;
            const props = { ...svg.props, className: svg.props.class };
            delete props.class;
            export default function() {
              return <svg { ...props }>{Children.only(svg.props.children)}</svg>
            }
          `, string(bytes))

				return api.OnLoadResult{
					Contents:   &contents,
					ResolveDir: filepath.Dir(args.Path),
					Loader:     api.LoaderJSX,
				}, nil
			})
	},
}
