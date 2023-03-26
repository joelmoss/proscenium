package api_test

import (
	"joelmoss/proscenium/golib/api"
	"joelmoss/proscenium/golib/importmap"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestImports(t *testing.T) {

	t.Run("exact matches", func(t *testing.T) {
		assert := assert.New(t)
		resolve := func(specifier string) string {
			importMap := []byte(`{
				"imports": {
					"foo": "/foo.mjs"
				}
			}`)

			parsedMap, _ := importmap.Parse(importMap, importmap.JsonType, api.TestEnv)
			resolvedPath, _ := api.ResolvePathFromImportMap(specifier, parsedMap, "/app/app.js")

			return resolvedPath
		}

		assert.Equal("/foo.mjs", resolve("foo"))
	})

	t.Run("should favor the most-specific key", func(t *testing.T) {
		resolve := func(specifier string) string {
			importMap := []byte(`{
				"imports": {
					"a": "/1",
          "a/": "/2/",
          "a/b": "/3",
          "a/b/": "/4/"
				}
			}`)

			parsedMap, _ := importmap.Parse(importMap, importmap.JsonType, api.TestEnv)
			resolvedPath, _ := api.ResolvePathFromImportMap(specifier, parsedMap, "/app/app.js")

			return resolvedPath
		}

		t.Run("Overlapping entries with trailing slashes", func(t *testing.T) {
			assert.Equal(t, "/1", resolve("a"))
			// assert.Equal(t, "/2/", resolve("a/"))
			// assert.Equal(t, "/2/x", resolve("a/x"))
			// assert.Equal(t, "/3", resolve("a/b"))
			// assert.Equal(t, "/4/", resolve("a/b/"))
			// assert.Equal(t, "/4/c", resolve("a/b/c"))
		})
	})

	t.Run("URL-like specifiers", func(t *testing.T) {
		resolve := func(specifier string) string {
			importMap := []byte(`{
				"imports": {
					"/lib/foo.mjs": "./more/bar.mjs",
					"./dotrelative/foo.mjs": "/lib/dot.mjs",
					"../dotdotrelative/foo.mjs": "/lib/dotdot.mjs",
					"/": "/lib/slash-only/",
					"./": "/lib/dotslash-only/",
					"/test/": "/lib/url-trailing-slash/",
					"./test/": "/lib/url-trailing-slash-dot/",
					"/test": "/lib/test1.mjs",
					"../test": "/lib/test2.mjs"
				}
			}`)

			parsedMap, _ := importmap.Parse(importMap, importmap.JsonType, api.TestEnv)
			resolvedPath, _ := api.ResolvePathFromImportMap(specifier, parsedMap, "/app/app.js")

			return resolvedPath
		}

		t.Run("Ordinary URL-like specifiers", func(t *testing.T) {
			assert.Equal(t, "/app/more/bar.mjs", resolve("/lib/foo.mjs"))
			assert.Equal(t, "/lib/dot.mjs", resolve("/app/dotrelative/foo.mjs"))
			assert.Equal(t, "/lib/dot.mjs", resolve("../app/dotrelative/foo.mjs"))
			assert.Equal(t, "/lib/dotdot.mjs", resolve("../dotdotrelative/foo.mjs"))
		})

		t.Run("Import map entries just composed from / and .", func(t *testing.T) {
			// All these should eventually resolve to index.js
			assert.Equal(t, "/lib/slash-only/", resolve("/"))
			assert.Equal(t, "/lib/slash-only/", resolve("../"))
			assert.Equal(t, "/lib/dotslash-only/", resolve("/app/"))
			assert.Equal(t, "/lib/dotslash-only/", resolve("../app/"))
		})

		t.Run("prefix-matched by keys with trailing slashes", func(t *testing.T) {
			assert.Equal(t, "/lib/url-trailing-slash/foo.mjs", resolve("/test/foo.mjs"))
			assert.Equal(t, "/lib/url-trailing-slash-dot/foo.mjs", resolve("/app/test/foo.mjs"))
		})

		t.Run("should use the last entry's address when URL-like specifiers parse to the same absolute URL", func(t *testing.T) {
			assert.Equal(t, "/lib/test2.mjs", resolve("/test"))
		})

		t.Run("backtracking", func(t *testing.T) {
			assert.Equal(t, "/lib/slash-only/", resolve("/"))
			assert.Equal(t, "/lib/slash-only/", resolve("/test/.."))
			assert.Equal(t, "/lib/slash-only/backtrack", resolve("/test/../backtrack"))
		})
	})

	t.Run("Tricky specifiers", func(t *testing.T) {
		resolve := func(specifier string) string {
			importMap := []byte(`{
				"imports": {
					"package/withslash": "/node_modules/package-with-slash/index.mjs",
					"not-a-package": "/lib/not-a-package.mjs",
					"only-slash/": "/lib/only-slash/",
					".": "/lib/dot.mjs",
					"..": "/lib/dotdot.mjs",
					"..\\": "/lib/dotdotbackslash.mjs",
					"%2E": "/lib/percent2e.mjs",
					"%2F": "/lib/percent2f.mjs"
				}
			}`)

			parsedMap, _ := importmap.Parse(importMap, importmap.JsonType, api.TestEnv)
			resolvedPath, ok := api.ResolvePathFromImportMap(specifier, parsedMap, "/app/app.js")

			if ok {
				return resolvedPath
			} else {
				return "failed to resolve"
			}
		}

		t.Run("explicitly-mapped specifiers that happen to have a slash", func(t *testing.T) {
			assert.Equal(t, "/node_modules/package-with-slash/index.mjs", resolve("package/withslash"))
		})

		t.Run("specifier with punctuation", func(t *testing.T) {
			assert.Equal(t, "/lib/dot.mjs", resolve("."))
			assert.Equal(t, "/lib/dotdot.mjs", resolve(".."))
			assert.Equal(t, "/lib/dotdotbackslash.mjs", resolve("..\\"))
			assert.Equal(t, "/lib/percent2e.mjs", resolve("%2E"))
			assert.Equal(t, "/lib/percent2f.mjs", resolve("%2F"))
		})

		t.Run("submodule of something not declared with a trailing slash should fail", func(t *testing.T) {
			assert.Equal(t, "failed to resolve", resolve("not-a-package/foo"))
		})

		t.Run("module for which only a trailing-slash version is present should fail", func(t *testing.T) {
			assert.Equal(t, "failed to resolve", resolve("only-slash"))
		})
	})
}

func TestScopes(t *testing.T) {
	resolve := func(specifier string, importer string, importMap []byte) string {
		parsedMap, _ := importmap.Parse(importMap, importmap.JsonType, api.TestEnv)
		resolvedPath, _ := api.ResolvePathFromImportMap(specifier, parsedMap, importer)

		return resolvedPath
	}

	t.Run("Fallback to toplevel and between scopes", func(t *testing.T) {
		importMap := []byte(`{
			"imports": {
				"a": "/a-1.mjs",
				"b": "/b-1.mjs",
				"c": "/c-1.mjs",
				"d": "/d-1.mjs"
			},
			"scopes": {
				"/scope2/": {
					"a": "/a-2.mjs",
					"d": "/d-2.mjs"
				},
				"/scope2/scope3/": {
					"b": "/b-3.mjs",
					"d": "/d-3.mjs"
				}
			}
		}`)

		t.Run("should fall back to `imports` when no scopes match", func(t *testing.T) {
			assert := assert.New(t)
			importer := "/scope1/foo.mjs"

			assert.Equal("/a-1.mjs", resolve("a", importer, importMap))
			assert.Equal("/b-1.mjs", resolve("b", importer, importMap))
			assert.Equal("/c-1.mjs", resolve("c", importer, importMap))
			assert.Equal("/d-1.mjs", resolve("d", importer, importMap))
		})

		t.Run("should use a direct scope override", func(t *testing.T) {
			assert := assert.New(t)
			importer := "/scope2/foo.mjs"

			assert.Equal("/a-2.mjs", resolve("a", importer, importMap))
			assert.Equal("/b-1.mjs", resolve("b", importer, importMap))
			assert.Equal("/c-1.mjs", resolve("c", importer, importMap))
			assert.Equal("/d-2.mjs", resolve("d", importer, importMap))
		})

		t.Run("should use an indirect scope override", func(t *testing.T) {
			assert := assert.New(t)
			importer := "/scope2/scope3/foo.mjs"

			assert.Equal("/a-2.mjs", resolve("a", importer, importMap))
			assert.Equal("/b-3.mjs", resolve("b", importer, importMap))
			assert.Equal("/c-1.mjs", resolve("c", importer, importMap))
			assert.Equal("/d-3.mjs", resolve("d", importer, importMap))
		})
	})

	t.Run("Package-like scenarios", func(t *testing.T) {
		importMap := []byte(`{
			"imports": {
				"moment": "/node_modules/moment/src/moment.js",
				"moment/": "/node_modules/moment/src/",
				"lodash-dot": "./node_modules/lodash-es/lodash.js",
				"lodash-dot/": "./node_modules/lodash-es/",
				"lodash-dotdot": "../node_modules/lodash-es/lodash.js",
				"lodash-dotdot/": "../node_modules/lodash-es/"
			},
			"scopes": {
				"/": {
					"moment": "/node_modules_3/moment/src/moment.js",
					"vue": "/node_modules_3/vue/dist/vue.runtime.esm.js"
				},
				"/js/": {
					"lodash-dot": "./node_modules_2/lodash-es/lodash.js",
					"lodash-dot/": "./node_modules_2/lodash-es/",
					"lodash-dotdot": "../node_modules_2/lodash-es/lodash.js",
					"lodash-dotdot/": "../node_modules_2/lodash-es/"
				}
			}
		}`)

		t.Run("Base URLs inside the scope should use the scope if the scope has matching keys", func(t *testing.T) {
			assert := assert.New(t)
			importer := "/js/app.mjs"

			assert.Equal("/js/node_modules_2/lodash-es/lodash.js", resolve("lodash-dot", importer, importMap))
			assert.Equal("/js/node_modules_2/lodash-es/foo", resolve("lodash-dot/foo", importer, importMap))
			assert.Equal("/node_modules_2/lodash-es/lodash.js", resolve("lodash-dotdot", importer, importMap))
			assert.Equal("/node_modules_2/lodash-es/foo", resolve("lodash-dotdot/foo", importer, importMap))
		})

		t.Run("Base URLs inside the scope fallback to less specific scope", func(t *testing.T) {
			assert := assert.New(t)
			importer := "/js/app.mjs"

			assert.Equal("/node_modules_3/moment/src/moment.js", resolve("moment", importer, importMap))
			assert.Equal("/node_modules_3/vue/dist/vue.runtime.esm.js", resolve("vue", importer, importMap))
		})

		t.Run("Base URLs inside the scope fallback to toplevel", func(t *testing.T) {
			assert := assert.New(t)
			importer := "/js/app.mjs"

			assert.Equal("/node_modules/moment/src/foo", resolve("moment/foo", importer, importMap))
		})

		t.Run("Base URLs outside a scope shouldn't use the scope even if the scope has matching keys", func(t *testing.T) {
			assert := assert.New(t)
			importer := "/app.mjs"

			assert.Equal("/node_modules/lodash-es/lodash.js", resolve("lodash-dot", importer, importMap))
		})
	})
}
