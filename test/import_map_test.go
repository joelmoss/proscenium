package proscenium_test

import (
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(import_map)", func() {
	It("produces error on invalid json", func() {
		result := Build("lib/foo.js", BuildOpts{ImportMap: `{[}]}`})

		Expect(result.Errors[0].Text).To(Equal("Failed to parse import map"))
	})

	When("import map is JS", func() {
		It("should parse", func() {
			result := Build("lib/import_map/as_js.js", BuildOpts{
				ImportMapPath: "config/import_maps/as.js",
			})

			Expect(result).To(ContainCode(`console.log("/lib/foo2.js");`))
		})

		It("produces error when invalid", func() {
			result := Build("lib/foo.js", BuildOpts{
				ImportMapPath: "config/import_maps/invalid.js",
			})

			Expect(result.Errors[0].Text).To(Equal("Failed to parse import map"))
		})
	})

	// import foo from 'foo'
	When("specifier is bare", func() {
		When("value starts with /", func() {
			It("resolves", func() {
				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "/lib/foo.js" }
					}`,
				})

				Expect(result).To(ContainCode(`console.log("/lib/foo.js");`))
			})
		})

		When("value starts with ./ or ../", func() {
			It("resolves", func() {
				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "../foo.js" }
					}`,
				})

				Expect(result).To(ContainCode(`console.log("/lib/foo.js");`))
			})
		})

		When("value is URL", func() {
			It("is not bundled", func() {
				MockURL("/foo.js", "console.log('foo');")

				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "https://proscenium.test/foo.js" }
					}`,
				})

				Expect(result).To(ContainCode(`
					import foo from "https://proscenium.test/foo.js";
				`))
			})
		})

		When("value is bare specifier", func() {
			It("resolves the value", func() {
				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "mypackage" }
					}`,
				})

				Expect(result).To(ContainCode(`
					console.log("node_modules/mypackage");
				`))
			})
		})

		When("value is directory containing an index file", func() {
			It("resolves the value to index file", func() {
				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "/lib/indexes" }
					}`,
				})

				Expect(result).To(ContainCode(`
					console.log("lib/indexes/index.js");
				`))
			})
		})

		It("resolves file without extension", func() {
			result := Build("lib/import_map/bare_specifier.js", BuildOpts{
				ImportMap: `{
					"imports": { "foo": "/lib/foo2" }
				}`,
			})

			Expect(result).To(ContainCode(`console.log("/lib/foo2.js");`))
		})
	})

	// import foo from "foo/one.js"
	When("key and value have trailing slash", func() {
		It("resolves", func() {
			result := Build("lib/import_map/path_prefix.js", BuildOpts{
				ImportMap: `{
					"imports": { "foo/": "./nested/foo/" }
				}`,
			})

			Expect(result).To(ContainCode(`console.log("/lib/import_map/nested/foo/one.js");`))
		})
	})

	It("resolves to URL", func() {
		result := Build("lib/import_map/to_url.js", BuildOpts{
			ImportMap: `{
				"imports": { "axios": "https://proscenium.test/axios.js" }
			}`,
		})

		Expect(result).To(ContainCode(`
			import axios from "https://proscenium.test/axios.js";
		`))
	})

	It("resolves to bare module", func() {
		result := Build("lib/import_map/bare_modules.js", BuildOpts{
			ImportMap: `{
				"imports": { "my-package": "mypackage" }
			}`,
		})

		Expect(result).To(ContainCode(`console.log("node_modules/mypackage");`))
	})

	// It("scopes", Pending, func() {
	// 	result := Build("lib/import_map/scopes.js", `{
	// 		"imports": {
	// 			"foo": "/lib/foo.js"
	// 		},
	// 		"scopes": {
	// 			"/lib/import_map/": {
	// 				"foo": "/lib/foo4.js"
	// 			}
	// 		}
	// 	}`)

	// 	Expect(result.OutputFiles[0].Contents).To(ContainCode(`import foo from "/lib/foo4.js";`))
	// })

})
