package importmap

import (
	"joelmoss/proscenium/internal/utils"
	"log"
	"path"
)

// type Scope struct {
// 	key   string
// 	value string
// }

// Resolves the `specifier` to a file system path, using the given `importMap` and `resolveDir`.
//
//   - specifier: The specifier to resolve.
//   - resolveDir: The path of the dir that is importing the specifier.
//   - root
//
// Returns the resolved specifier, and a boolean indicating whether the resolution was successful.
// It is important to note that the resolved specifier could be an absolute file system path, an
// HTTP(S) URL, or a bare module specifier.
func Resolve(specifier string, resolveDir string, root string) (string, bool) {
	if Contents == nil || len(Contents.Imports) == 0 {
		return "", false
	}

	// Sort and normalize the "imports" of the import map.
	// See https://html.spec.whatwg.org/multipage/webappapis.html#sorting-and-normalizing-a-module-specifier-map
	// log.Printf("[importMap] Resolving %v in %v from %v import(s)", specifier, resolveDir, len(Contents.Imports))

	normalizedImports := make(map[string]string)

	// Sort and normalize imports.
	for key, value := range Contents.Imports {
		if key == "" || value == "" {
			continue
		}

		// Normalize the value.
		value = normalize(value, resolveDir, root)

		normalizedImports[key] = value
	}

	value, found := normalizedImports[specifier]
	if found {
		log.Printf("[importMap] match! %v => %v", specifier, value)
		return value, true
	}

	return "", false
}

// Returns the full and absolute file system path of the given `pathValue`. If the path is a bare
// module, then it is returned as-is. Otherwise, it is resolved relative to the given `resolveDir`.
func normalize(pathValue string, resolveDir string, root string) string {
	if utils.IsBareModule(pathValue) || utils.IsUrl(pathValue) {
		return pathValue
	} else if path.IsAbs(pathValue) {
		return path.Join(root, pathValue)
	} else {
		return path.Join(resolveDir, pathValue)
	}
}

// func oldResolve(specifier string, imap *types.ImportMap, importer string) (string, bool) {
// 	// Normalize the importer as an absolute path.
// 	base := path.Dir(importer)

// 	// Scoped match?
// 	matchedScopes := []Scope{}
// 	for scopePrefix, scopeImports := range imap.Scopes {
// 		pp.Println(">>> ")
// 		pp.Println(scopePrefix, scopeImports)

// 		pp.Println(101, strings.HasSuffix(scopePrefix, "/"))
// 		pp.Println(102, strings.HasPrefix(base, scopePrefix))

// 		if strings.HasSuffix(scopePrefix, "/") && strings.HasPrefix(base, scopePrefix) {
// 			resolvedPath, matched := resolveSpecifier(specifier, scopeImports, importer)
// 			if matched {
// 				pp.Println(111, scopePrefix, resolvedPath)
// 				matchedScopes = append(matchedScopes, Scope{scopePrefix, resolvedPath})
// 			}
// 		} else {

// 			normScope := path.Join(base, scopePrefix)

// 			pp.Println("normScope:", normScope, scopePrefix)
// 			// pp.Println(201, strings.HasSuffix(scopePrefix, "/"))
// 			// pp.Println(202, strings.HasPrefix(base, normScope))

// 			if base != normScope && strings.HasPrefix(base, normScope) {
// 				resolvedPath, matched := resolveSpecifier(specifier, scopeImports, importer)
// 				if matched {
// 					pp.Println(222, scopePrefix, resolvedPath)
// 					matchedScopes = append(matchedScopes, Scope{scopePrefix, resolvedPath})
// 				}
// 			}
// 		}
// 	}

// 	if len(matchedScopes) > 0 {
// 		sort.Slice(matchedScopes, func(i, j int) bool {
// 			return len(matchedScopes[i].Key) > len(matchedScopes[j].Key)
// 		})

// 		if !strings.HasPrefix(matchedScopes[0].Value, "/") {
// 			return path.Join(matchedScopes[0].Key, matchedScopes[0].Value), true
// 		}
// 		return matchedScopes[0].Value, true
// 	}

// 	// Direct match?
// 	return resolveSpecifier(specifier, imap.Imports, base)
// }

// func resolveSpecifier(specifier string, mapImports map[string]string, base string) (string, bool) {
// 	// Normalise the specifier relative to the base path.
// 	normSpecifier := specifier
// 	if !path.IsAbs(specifier) {
// 		normSpecifier = path.Join(base, specifier)
// 	} else {
// 		normSpecifier = path.Clean(normSpecifier)
// 	}

// 	pp.Printf("specifier(%s), normSpecifier(%s), base(%s)\n", specifier, normSpecifier, base)

// 	keys := make([]string, 0, len(mapImports))
// 	for key := range mapImports {
// 		keys = append(keys, key)
// 	}

// 	// Sort the keys by longest first
// 	sort.Strings(keys)
// 	sort.Slice(keys, func(i, j int) bool {
// 		return len(keys[i]) > len(keys[j])
// 	})

// 	// Find all specifiers where the key and value have a trailing slash, and the path starts with the
// 	// key.
// 	for _, key := range keys {
// 		value := mapImports[key]
// 		normKey := key

// 		if !path.IsAbs(key) {
// 			normKey = path.Join(base, key)
// 		}

// 		pp.Printf("- %s[%s] => %s\n", key, normKey, value)

// 		// Match if the key and value both have a trailing slash...
// 		if strings.HasSuffix(key, "/") && strings.HasSuffix(value, "/") {
// 			// ...and the normalised specifier starts with the key.
// 			if strings.HasPrefix(normSpecifier, normKey) {
// 				pp.Printf("  ✅ (2)")
// 				pp.Printf("  %s starts with %s\n", normSpecifier, normKey)

// 				if IsBareModule(specifier) {
// 					return "", false
// 				}

// 				if strings.HasSuffix(specifier, "/") {
// 					return value, true
// 				}

// 				// Replace the key with the value as a prefix of the specifier.
// 				unprefixed, _ := strings.CutPrefix(normSpecifier, normKey)
// 				pp.Println(normKey, unprefixed)

// 				if unprefixed == "" {
// 					return value, true
// 				} else {
// 					return path.Join(value, unprefixed), true
// 				}
// 			}

// 			// ...and the normalised specifier starts with the key.
// 			if strings.HasPrefix(normSpecifier, key) {
// 				pp.Printf("  ✅ (3)")
// 				pp.Printf("  %s starts with %s\n", normSpecifier, key)

// 				if strings.HasSuffix(specifier, "/") {
// 					return value, true
// 				}

// 				// Replace the key with the value as a prefix of the specifier.
// 				unprefixed, _ := strings.CutPrefix(specifier, key)
// 				return path.Join(value, unprefixed), true
// 			}
// 		}

// 		// Match if the normalised key equals the normalised specifier.
// 		if normKey == normSpecifier {
// 			pp.Printf("  normKey(%s) == normSpecifier(%s) ?\n", normKey, normSpecifier)
// 			pp.Printf("  ✅ (4)\n")

// 			if !path.IsAbs(value) {
// 				return path.Join(base, value), true
// 			}

// 			return value, true
// 		}

// 		// Match if the normalised key equals the specifier.
// 		if normKey == specifier {
// 			pp.Printf("  normKey(%s) == specifier(%s) ?\n", normKey, specifier)
// 			pp.Printf("  ✅ (5)\n")
// 			return value, true
// 		}
// 	}

// 	return "", false
// }
