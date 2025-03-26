package importmap

import (
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"log"
	"path"
	"sort"
	"strings"
)

// type Scope struct {
// 	key   string
// 	value string
// }

type importEntry struct {
	value                 string
	keyHasTrailingSlash   bool
	valueHasTrailingSlash bool
}

// Resolves the given `specifier`.
//
//   - specifier: The specifier to resolve.
//   - resolveDir: The path of the dir that is importing the specifier.
//
// Returns the resolved specifier, and a boolean indicating whether the resolution was successful.
// It is important to note that the resolved specifier could be an absolute URL path, an HTTP(S)
// URL, or a bare module specifier.
func Resolve(specifier string, resolveDir string) (string, error) {
	imports, err := Imports()
	if err != nil {
		return specifier, err
	} else if len(imports) == 0 {
		return specifier, nil
	}
	resolveDir = strings.TrimPrefix(resolveDir, types.Config.RootPath)
	normalizedImports := make(map[string]importEntry)

	// Sort and normalize imports.
	for key, value := range imports {
		if key == "" || value == "" {
			continue
		}

		// key = normalizeKey(key, resolveDir)
		value = normalizeValue(value, resolveDir)
		keyHasTrailingSlash := strings.HasSuffix(key, "/")
		valueHasTrailingSlash := strings.HasSuffix(value, "/")

		if keyHasTrailingSlash && !valueHasTrailingSlash {
			log.Printf("[proscenium] importmap key `%v` ends with '/', but value `%v` does not!",
				specifier, value)
			continue
		}

		normalizedImports[key] = importEntry{value, keyHasTrailingSlash, valueHasTrailingSlash}
	}

	debug.Debug("[proscenium] importmap match?", specifier, resolveDir)

	// Sort the keys of the normalized imports by longest first.
	importKeys := make([]string, 0, len(normalizedImports))
	for key := range normalizedImports {
		importKeys = append(importKeys, key)
	}
	sort.Strings(importKeys)
	sort.Slice(importKeys, func(i, j int) bool {
		return len(importKeys[i]) > len(importKeys[j])
	})

	// Find the first entry in the normalized import map that matches the specifier.
	matchedPath, found := func() (matchedPath string, success bool) {
		for _, key := range importKeys {
			entry := normalizedImports[key]

			// Match if the key and value both have a trailing slash, and the specifier starts with the
			// key.
			if entry.keyHasTrailingSlash && entry.valueHasTrailingSlash {
				trimmed, ok := strings.CutPrefix(specifier, key)
				if ok {
					return path.Join(entry.value, trimmed), true
				}

				continue
			}

			// Exact match: specifier == key
			if key == specifier {
				return entry.value, true
			}
		}

		return "", false
	}()

	if found {
		debug.Debug("[proscenium] importmap match! `%v` => `%v`", specifier, matchedPath)

		if types.Config.Debug {
			log.Printf("[proscenium] importmap match! `%v` => `%v`", specifier, matchedPath)
		}

		return matchedPath, nil
	}

	return specifier, nil
}

func normalizeKey(key string, resolveDir string) string {
	return key
}

// Returns the absolute URL path of the given `pathValue`. If the path is a relative path (ie.
// starts with `./` or `../`) it is resolved relative to the given `resolveDir`.
//
// TODO: resolve indexes here, instead of passing to esbuild to resolve - the latter of which should
// be slower.
func normalizeValue(pathValue string, resolveDir string) string {
	hasTrailingSlash := strings.HasSuffix(pathValue, "/")

	if utils.PathIsRelative(pathValue) {
		newValue := path.Join(resolveDir, pathValue)

		if hasTrailingSlash {
			return newValue + "/"
		}
		return newValue
	}

	return pathValue

	// if utils.IsUrl(pathValue) {
	// 	return pathValue
	// }

	// if utils.PathIsRelative(pathValue) || path.IsAbs(pathValue) {
	// 	np := strings.TrimPrefix(path.Join(resolveDir, pathValue), types.Config.RootPath)
	// 	pp.Println(np)
	// 	return pathValue
	// }

	// if utils.IsBareModule(pathValue) || path.IsAbs(pathValue) {
	// 	return pathValue
	// }

	// // Path is relative, so resolve it relative to the resolveDir, then strip the root from the start.
	// return strings.TrimPrefix(path.Join(resolveDir, pathValue), types.Config.RootPath)
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
