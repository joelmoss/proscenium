package plugin

import (
	"fmt"
	"joelmoss/proscenium/internal/utils"
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

				contents, err := func() (string, error) {
					if utils.IsUrl(args.Path) {
						return DownloadURL(args.Path)
					} else {
						bytes, err := os.ReadFile(args.Path)
						if err != nil {
							return "", err
						}

						return string(bytes), nil
					}
				}()

				if err != nil {
					return api.OnLoadResult{}, err
				}

				contents = fmt.Sprintf(`
					import { cloneElement, Children } from 'react';
					const svg = %s;
					const props = { ...svg.props, className: svg.props.class };
					delete props.class;
					export default function() {
						return <svg { ...props }>{Children.only(svg.props.children)}</svg>
					}
				`, contents)

				return api.OnLoadResult{
					Contents:   &contents,
					ResolveDir: filepath.Dir(args.Path),
					Loader:     api.LoaderJSX,
				}, nil
			})
	},
}
