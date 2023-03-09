package utils

import (
	"joelmoss/proscenium/golib/importmap"

	"github.com/evanw/esbuild/pkg/api"
)

func Resolve(args *api.OnResolveArgs, imap *importmap.ImportMap) api.OnResolveResult {
	if imap != nil {
		// Find the path in the import map
		if specifier, ok := imap.Imports[args.Path]; ok {
			return api.OnResolveResult{
				Path:     specifier,
				External: true,
			}
		}
	}

	return api.OnResolveResult{}
}
