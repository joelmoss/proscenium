package internal

import (
	"path"
	"regexp"
	"sort"
	"strings"

	"github.com/k0kubun/pp/v3"
)

type Scope struct {
	Key   string
	Value string
}

// Resolves the specifier to a path, using the import map and the importer, and returns the resolved
// path and a boolean indicating whether the resolution was successful.
func ResolvePathFromImportMap(specifier string, imap *ImportMap, importer string) (string, bool) {
	// Normalize the importer as an absolute path.
	base := path.Dir(importer)

	// Scoped match?
	matchedScopes := []Scope{}
	for scopePrefix, scopeImports := range imap.Scopes {
		pp.Println(">>> ")
		pp.Println(scopePrefix, scopeImports)

		pp.Println(101, strings.HasSuffix(scopePrefix, "/"))
		pp.Println(102, strings.HasPrefix(base, scopePrefix))

		if strings.HasSuffix(scopePrefix, "/") && strings.HasPrefix(base, scopePrefix) {
			resolvedPath, matched := resolveSpecifier(specifier, scopeImports, importer)
			if matched {
				pp.Println(111, scopePrefix, resolvedPath)
				matchedScopes = append(matchedScopes, Scope{scopePrefix, resolvedPath})
			}
		} else {

			normScope := path.Join(base, scopePrefix)

			pp.Println("normScope:", normScope, scopePrefix)
			// pp.Println(201, strings.HasSuffix(scopePrefix, "/"))
			// pp.Println(202, strings.HasPrefix(base, normScope))

			if base != normScope && strings.HasPrefix(base, normScope) {
				resolvedPath, matched := resolveSpecifier(specifier, scopeImports, importer)
				if matched {
					pp.Println(222, scopePrefix, resolvedPath)
					matchedScopes = append(matchedScopes, Scope{scopePrefix, resolvedPath})
				}
			}
		}
	}

	if len(matchedScopes) > 0 {
		sort.Slice(matchedScopes, func(i, j int) bool {
			return len(matchedScopes[i].Key) > len(matchedScopes[j].Key)
		})

		if !strings.HasPrefix(matchedScopes[0].Value, "/") {
			return path.Join(matchedScopes[0].Key, matchedScopes[0].Value), true
		}
		return matchedScopes[0].Value, true
	}

	// Direct match?
	return resolveSpecifier(specifier, imap.Imports, base)
}

func resolveSpecifier(specifier string, mapImports map[string]string, base string) (string, bool) {
	// Normalise the specifier relative to the base path.
	normSpecifier := specifier
	if !path.IsAbs(specifier) {
		normSpecifier = path.Join(base, specifier)
	} else {
		normSpecifier = path.Clean(normSpecifier)
	}

	pp.Printf("specifier(%s), normSpecifier(%s), base(%s)\n", specifier, normSpecifier, base)

	keys := make([]string, 0, len(mapImports))
	for key := range mapImports {
		keys = append(keys, key)
	}

	// Sort the keys by longest first
	sort.Strings(keys)
	sort.Slice(keys, func(i, j int) bool {
		return len(keys[i]) > len(keys[j])
	})

	// Find all specifiers where the key and value have a trailing slash, and the path starts with the
	// key.
	for _, key := range keys {
		value := mapImports[key]
		normKey := key

		if !path.IsAbs(key) {
			normKey = path.Join(base, key)
		}

		pp.Printf("- %s[%s] => %s\n", key, normKey, value)

		// Match if the key and value both have a trailing slash...
		if strings.HasSuffix(key, "/") && strings.HasSuffix(value, "/") {
			// ...and the normalised specifier starts with the key.
			if strings.HasPrefix(normSpecifier, normKey) {
				pp.Printf("  ✅ (2)")
				pp.Printf("  %s starts with %s\n", normSpecifier, normKey)

				if IsBareModule(specifier) {
					return "", false
				}

				if strings.HasSuffix(specifier, "/") {
					return value, true
				}

				// Replace the key with the value as a prefix of the specifier.
				unprefixed, _ := strings.CutPrefix(normSpecifier, normKey)
				pp.Println(normKey, unprefixed)

				if unprefixed == "" {
					return value, true
				} else {
					return path.Join(value, unprefixed), true
				}
			}

			// ...and the normalised specifier starts with the key.
			if strings.HasPrefix(normSpecifier, key) {
				pp.Printf("  ✅ (3)")
				pp.Printf("  %s starts with %s\n", normSpecifier, key)

				if strings.HasSuffix(specifier, "/") {
					return value, true
				}

				// Replace the key with the value as a prefix of the specifier.
				unprefixed, _ := strings.CutPrefix(specifier, key)
				return path.Join(value, unprefixed), true
			}
		}

		// Match if the normalised key equals the normalised specifier.
		if normKey == normSpecifier {
			pp.Printf("  normKey(%s) == normSpecifier(%s) ?\n", normKey, normSpecifier)
			pp.Printf("  ✅ (4)\n")

			if !path.IsAbs(value) {
				return path.Join(base, value), true
			}

			return value, true
		}

		// Match if the normalised key equals the specifier.
		if normKey == specifier {
			pp.Printf("  normKey(%s) == specifier(%s) ?\n", normKey, specifier)
			pp.Printf("  ✅ (5)\n")
			return value, true
		}
	}

	return "", false
}

func IsBareModule(name string) bool {
	var re = regexp.MustCompile(`(?m)^(@[a-z0-9-~][a-z0-9-._~]*\/)?[a-z0-9-~][a-z0-9-._~]*$`)
	return re.MatchString(name)
}
