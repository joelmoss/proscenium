package internal

import (
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

func Resolve(args esbuild.OnResolveArgs, imap *ImportMap, root string) esbuild.OnResolveResult {
	if imap != nil {
		// Look for a match in the import map
		base := strings.TrimPrefix(args.Importer, root)
		resolvedImport, matched := ResolvePathFromImportMap(args.Path, imap, base)
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
