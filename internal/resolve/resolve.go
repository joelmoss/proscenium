package resolve

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

func Resolve(args esbuild.OnResolveArgs, imap *types.ImportMap, root string) esbuild.OnResolveResult {
	if imap != nil {
		// Look for a match in the import map
		base := strings.TrimPrefix(args.Importer, root)
		resolvedImport, matched := importmap.ResolvePathFromImportMap(args.Path, imap, base)
		if matched {
			return esbuild.OnResolveResult{
				Path:     resolvedImport,
				External: true,
			}
		}
	}

	return esbuild.OnResolveResult{
		Path:     args.Path,
		External: true,
	}

	// return esbuild.OnResolveResult{}
}
