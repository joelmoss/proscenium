package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	. "joelmoss/proscenium/test/support"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(import_map)", func() {
	When("import map is JS", func() {
		It("should parse", func() {
			importmap.NewJavaScriptImportMap([]byte(`
				env => ({
					imports: {
						pkg: env === 'test' ? '/lib/foo2.js' : '/lib/foo3.js'
					}
				})
			`))

			Expect(b.Build("lib/import_map/as_js.js")).To(ContainCode(`console.log("/lib/foo2.js");`))
		})

		It("errors when invalid contents", func() {
			result := importmap.NewJavaScriptImportMap([]byte(`()(())`))

			Expect(strings.HasPrefix(result.Error(), "Cannot read import map:")).To(BeTrue())
		})

		It("populates build errors when invalid", func() {
			importmap.TEST_IMPORT_MAP_FILE = "config/import_maps/invalid.js"
			importmap.TEST_IMPORT_MAP_TYPE = importmap.JavascriptType

			result := importmap.NewJavaScriptImportMap([]byte(`()(())`))

			Expect(strings.HasPrefix(result.Error(), "Cannot read import map:")).To(BeTrue())
		})
	})

	It("errors with invalid json", func() {
		result := importmap.NewJsonImportMap([]byte(`{`))

		Expect(strings.HasPrefix(result.Error(), "Cannot read import map:")).To(BeTrue())
	})

	It("populates build errors with invalid json", func() {
		result := importmap.NewJsonImportMap([]byte(`{`))

		Expect(strings.HasPrefix(result.Error(), "Cannot read import map:")).To(BeTrue())
	})

	// import foo from 'foo'
	When("specifier is bare", func() {
		When("value starts with /", func() {
			It("resolves", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo": "/lib/foo.js" }
				}`))

				result := b.Build("lib/import_map/bare_specifier.js")

				Expect(result).To(ContainCode(`console.log("/lib/foo.js");`))
			})
		})

		When("value starts with ./ or ../", func() {
			It("resolves", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo": "../foo.js" }
				}`))

				result := b.Build("lib/import_map/bare_specifier.js")

				Expect(result).To(ContainCode(`console.log("/lib/foo.js");`))
			})
		})

		When("value is URL", func() {
			It("is not bundled", func() {
				MockURL("/foo.js", "console.log('foo');")

				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo": "https://proscenium.test/foo.js" }
				}`))

				result := b.Build("lib/import_map/bare_specifier.js")

				Expect(result).To(ContainCode(`
					import foo from "https://proscenium.test/foo.js";
				`))
			})
		})

		When("value is bare specifier", func() {
			It("resolves the value", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo": "mypackage" }
				}`))

				result := b.Build("lib/import_map/bare_specifier.js")

				Expect(result).To(ContainCode(`
					console.log("node_modules/mypackage");
				`))
			})
		})

		When("value is directory containing an index file", func() {
			It("resolves the value to index file", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo": "/lib/indexes" }
				}`))

				result := b.Build("lib/import_map/bare_specifier.js")

				Expect(result).To(ContainCode(`
					console.log("lib/indexes/index.js");
				`))
			})
		})

		It("resolves file without extension", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "foo": "/lib/foo2" }
			}`))

			result := b.Build("lib/import_map/bare_specifier.js")

			Expect(result).To(ContainCode(`console.log("/lib/foo2.js");`))
		})
	})

	// import foo from "foo/one.js"
	When("key and value have trailing slash", func() {
		It("resolves", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "foo/": "./nested/foo/" }
			}`))

			result := b.Build("lib/import_map/path_prefix.js")

			Expect(result).To(ContainCode(`console.log("/lib/import_map/nested/foo/one.js");`))
		})
	})

	It("resolves to URL", func() {
		importmap.NewJsonImportMap([]byte(`{
			"imports": { "axios": "https://proscenium.test/axios.js" }
		}`))

		result := b.Build("lib/import_map/to_url.js")

		Expect(result).To(ContainCode(`
			import axios from "https://proscenium.test/axios.js";
		`))
	})

	It("resolves to bare module", func() {
		importmap.NewJsonImportMap([]byte(`{
			"imports": { "my-package": "mypackage" }
		}`))

		result := b.Build("lib/import_map/bare_modules.js")

		Expect(result).To(ContainCode(`console.log("node_modules/mypackage");`))
	})

	// It("scopes", Pending, func() {
	// 	importmap.NewJsonImportMap([]byte(`{
	// 		"imports": {
	// 			"foo": "/lib/foo.js"
	// 		},
	// 		"scopes": {
	// 			"/lib/import_map/": {
	// 				"foo": "/lib/foo4.js"
	// 			}
	// 		}
	// 	}`))

	// 	result := b.Build("lib/import_map/scopes.js")

	// 	Expect(result.OutputFiles[0].Contents).To(ContainCode(`import foo from "/lib/foo4.js";`))
	// })
})
