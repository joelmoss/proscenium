package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("import maps", func() {
	It("errors with invalid json", func() {
		result := importmap.NewJsonImportMap([]byte(`{`))

		Expect(strings.HasPrefix(result.Error(), "Cannot read import map:")).To(BeTrue())
	})

	It("populates build errors with invalid json", func() {
		result := importmap.NewJsonImportMap([]byte(`{`))

		Expect(strings.HasPrefix(result.Error(), "Cannot read import map:")).To(BeTrue())
	})

	When("import map is JS", func() {
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

	Describe("bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
		})

		It("parses import map as JS", func() {
			importmap.NewJavaScriptImportMap([]byte(`
				env => ({
					imports: {
						pkg: env === 'test' ? '/lib/foo2.js' : '/lib/foo3.js'
					}
				})
			`))

			_, code, _ := b.BuildToString("lib/import_map/as_js.js")

			Expect(code).To(ContainCode(`console.log("/lib/foo2.js");`))
		})

		// import foo from 'foo'
		Describe("bare specifier", func() {
			When("value starts with /", func() {
				It("resolves", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "/lib/foo.js" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`console.log("/lib/foo.js");`))
				})
			})

			When("value starts with ./ or ../", func() {
				It("resolves", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "../foo.js" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`console.log("/lib/foo.js");`))
				})
			})

			When("value is URL", func() {
				It("is not bundled", func() {
					MockURL("/foo.js", "console.log('foo');")

					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "https://proscenium.test/foo.js" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`import "https://proscenium.test/foo.js";`))
				})
			})

			When("value is bare specifier", func() {
				It("resolves the value", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "pkg" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`console.log("pkg/index.js")`))
				})
			})

			When("value is directory containing an index file", func() {
				It("resolves the value to index file", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "/lib/indexes" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`
						console.log("lib/indexes/index.js");
					`))
				})
			})

			It("resolves file without extension", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo": "/lib/foo2" }
				}`))

				_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

				Expect(code).To(ContainCode(`console.log("/lib/foo2.js");`))
			})
		})

		// import foo from "foo/one.js"
		When("key and value have trailing slash", func() {
			It("resolves", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo/": "./nested/foo/" }
			}`))

				_, code, _ := b.BuildToString("lib/import_map/path_prefix.js")

				Expect(code).To(ContainCode(`console.log("/lib/import_map/nested/foo/one.js");`))
			})
		})

		It("resolves to URL", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "axios": "https://proscenium.test/axios.js" }
			}`))

			_, code, _ := b.BuildToString("lib/import_map/to_url.js")

			Expect(code).To(ContainCode(`
				import axios from "https://proscenium.test/axios.js";
			`))
		})

		It("resolves to bare module", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "my-package": "pkg" }
			}`))

			_, code, _ := b.BuildToString("lib/import_map/bare_modules.js")

			Expect(code).To(ContainCode(`console.log("pkg/index.js");`))
		})

		XIt("scopes", Pending, func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": {
					"foo": "/lib/foo.js"
				},
				"scopes": {
					"/lib/import_map/": {
						"foo": "/lib/foo4.js"
					}
				}
			}`))

			_, code, _ := b.BuildToString("lib/import_map/scopes.js")

			Expect(code).To(ContainCode(`import foo from "/lib/foo4.js";`))
		})
	})

	Describe("bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
		})

		It("parses import map as JS", func() {
			importmap.NewJavaScriptImportMap([]byte(`
					env => ({
						imports: {
							pkg: env === 'test' ? '/lib/foo2.js' : '/lib/foo3.js'
						}
					})
				`))

			_, code, _ := b.BuildToString("lib/import_map/as_js.js")

			Expect(code).To(ContainCode(`import pkg from "/lib/foo2.js";`))
		})

		It("parse import map as JSON", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "foo": "/lib/foo.js" }
			}`))

			_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

			Expect(code).To(ContainCode(`import "/lib/foo.js";`))
		})

		// import foo from 'foo'
		Describe("bare specifier", func() {
			When("value starts with /", func() {
				It("resolves", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "/lib/foo.js" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`import "/lib/foo.js";`))
				})
			})

			When("value starts with ./ or ../", func() {
				It("resolves", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "../foo.js" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`import "/lib/foo.js";`))
				})
			})

			When("value is URL", func() {
				It("is not bundled", func() {
					MockURL("/foo.js", "console.log('foo');")

					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "https://proscenium.test/foo.js" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`import "https://proscenium.test/foo.js";`))
				})
			})

			When("value is bare specifier", func() {
				It("resolves the value", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "pkg" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`import "/node_modules/pkg/index.js";`))
				})
			})

			When("value is directory containing an index file", func() {
				It("resolves the value to index file", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": { "foo": "/lib/indexes" }
					}`))

					_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

					Expect(code).To(ContainCode(`import "/lib/indexes/index.js";`))
				})
			})

			It("resolves file without extension", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo": "/lib/foo2" }
				}`))

				_, code, _ := b.BuildToString("lib/import_map/bare_specifier.js")

				Expect(code).To(ContainCode(`import "/lib/foo2.js";`))
			})
		})

		// import foo from "foo/one.js"
		When("key and value have trailing slash", func() {
			It("resolves", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": { "foo/": "./nested/foo/" }
			}`))

				_, code, _ := b.BuildToString("lib/import_map/path_prefix.js")

				Expect(code).To(ContainCode(`
					import foo from "/lib/import_map/nested/foo/one.js";
				`))
			})
		})

		It("resolves to URL", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "axios": "https://proscenium.test/axios.js" }
			}`))

			_, code, _ := b.BuildToString("lib/import_map/to_url.js")

			Expect(code).To(ContainCode(`
				import axios from "https://proscenium.test/axios.js";
			`))
		})

		It("resolves to bare module", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "my-package": "pkg" }
			}`))

			_, code, _ := b.BuildToString("lib/import_map/bare_modules.js")

			Expect(code).To(ContainCode(`import mypackage from "/node_modules/pkg/index.js";`))
		})
	})
})
