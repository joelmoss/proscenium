package resolver

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"path"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
	"github.com/k0kubun/pp/v3"
)

// Resolves the given path to an absolute file system path.
func Absolute(pathToResolve string, root string) (string, bool) {
	pp.Println(pathToResolve)

	// Absolute path - append to root. This enables absolute path imports (eg, import '/lib/foo').
	if strings.HasPrefix(pathToResolve, "/") {
		pathToResolve = path.Join(root, pathToResolve)
	}

	return pathToResolve, true
}

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
