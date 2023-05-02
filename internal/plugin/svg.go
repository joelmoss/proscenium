package plugin

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/evanw/esbuild/pkg/api"
)

// When importing an svg image from a jsx module, the svg is exported as a react component. It is
// assumed that the SVG file is located in /public.
var Svg = api.Plugin{
	Name: "svg",
	Setup: func(build api.PluginBuild) {
		build.OnLoad(api.OnLoadOptions{Filter: `.*`, Namespace: "svgFromJsx"},
			func(args api.OnLoadArgs) (api.OnLoadResult, error) {
				// pp.Println("[svg] namespace(svgFromJsx)", args)

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
