package api

import (
	"sort"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

func Resolve(args *esbuild.OnResolveArgs, imap *ImportMap) esbuild.OnResolveResult {
	if imap != nil {
		// Find the path in the import map

		// Find the first specifier that is an exact key match.
		if specifier, ok := imap.Imports[args.Path]; ok {
			return esbuild.OnResolveResult{
				Path:     specifier,
				External: true,
			}
		} else {
			matchedKeys := make([]string, 0, len(imap.Imports))

			// Find all specifiers where the key and value have a trailing slash, and the path starts with the key.
			for key, value := range imap.Imports {
				if strings.HasSuffix(key, "/") && strings.HasSuffix(value, "/") && strings.HasPrefix(args.Path, key) {
					matchedKeys = append(matchedKeys, key)
				}
			}

			// Sort the matched keys so longest is first, then use that key.
			if len(matchedKeys) > 0 {
				sort.Sort(sort.Reverse(sort.StringSlice(matchedKeys)))

				key := matchedKeys[0]
				value := imap.Imports[key]

				// In the path, replace the key with the value as a prefix.
				if after, ok := strings.CutPrefix(args.Path, key); ok {
					return esbuild.OnResolveResult{
						Path:     value + after,
						External: true,
					}
				}
			}

		}
	}

	return esbuild.OnResolveResult{}
}
