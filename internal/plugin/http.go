package plugin

import (
	"joelmoss/proscenium/internal/utils"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

var Http = esbuild.Plugin{
	Name: "http",
	Setup: func(build esbuild.PluginBuild) {
		// Mark all paths starting with "http://" or "https://" as external
		build.OnResolve(esbuild.OnResolveOptions{Filter: `^https?://`},
			func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
				// SVG files imported from JSX should be downloaded and bundled as JSX with the svgFromJsx
				// namespace.
				if utils.IsSvgImportedFromJsx(args.Path, args) {
					return esbuild.OnResolveResult{
						Path:      args.Path,
						Namespace: "svgFromJsx",
					}, nil
				}

				return esbuild.OnResolveResult{
					Path:     args.Path,
					External: true,
				}, nil
			})
	},
}
