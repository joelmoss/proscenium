package builder_test

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	. "joelmoss/proscenium/internal/testing"
	"joelmoss/proscenium/internal/types"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/url", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		plugin.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	When("entry point is encoded URL", func() {
		It("bundles js", func() {
			MockURL("/foo.js", "export default 'Hello World'")

			Expect(Build("https%3A%2F%2Fproscenium.test%2Ffoo.js")).To(ContainCode(`= "Hello World";`))
		})

		It("should cache", func() {
			MockURL("/foo.js", "export default 'Hello World'")
			Expect(Build("https%3A%2F%2Fproscenium.test%2Ffoo.js")).To(ContainCode(`= "Hello World";`))

			MockURL("/foo.js", "invalid code")
			Expect(Build("https%3A%2F%2Fproscenium.test%2Ffoo.js")).To(ContainCode(`= "Hello World";`))
		})

		It("bundles css", func() {
			MockURL("/foo.css", "body { color: red; }")

			Expect(Build("https%3A%2F%2Fproscenium.test%2Ffoo.css")).To(ContainCode(`body { color: red; }`))
		})

		When("bundling", func() {
			It("bundles js", func() {
				MockURL("/foo.js", "export default 'Hello World'")

				result := Build("https%3A%2F%2Fproscenium.test%2Ffoo.js", BuildOpts{Bundle: true})
				Expect(result).To(ContainCode(`= "Hello World";`))
			})

			It("bundles css", func() {
				MockURL("/foo.css", "body { color: red; }")

				result := Build("https%3A%2F%2Fproscenium.test%2Ffoo.css", BuildOpts{Bundle: true})
				Expect(result).To(ContainCode(`body { color: red; }`))
			})

			It("should cache", func() {
				MockURL("/foo.css", "body { color: red; }")
				Expect(Build("https%3A%2F%2Fproscenium.test%2Ffoo.css", BuildOpts{Bundle: true})).To(ContainCode(`body { color: red; }`))

				MockURL("/foo.css", "invalid code")
				Expect(Build("https%3A%2F%2Fproscenium.test%2Ffoo.css", BuildOpts{Bundle: true})).To(ContainCode(`body { color: red; }`))
			})
		})
	})

	When("importing a URL", func() {
		It("should encode URL", func() {
			Expect(Build("lib/import_url.js")).To(ContainCode(`
				import myFunction from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
			`))
		})

		When("bundling", func() {
			It("should encode URL", func() {
				Expect(Build("lib/import_url.js", BuildOpts{Bundle: true})).To(ContainCode(`
				import myFunction from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
			`))
			})
		})
	})

	When("import map resolves to url", func() {
		It("should encode URL", func() {
			result := Build("lib/import_map/bare_specifier.js", BuildOpts{ImportMap: `{
				"imports": { "foo": "https://proscenium.test/import-url-module.js" }
			}`})

			Expect(result).To(ContainCode(`
				import foo from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
			`))
		})

		When("bundling", func() {
			It("should encode URL", func() {
				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					Bundle: true,
					ImportMap: `{
						"imports": { "foo": "https://proscenium.test/import-url-module.js" }
					}`,
				})

				Expect(result).To(ContainCode(`
					import foo from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
				`))
			})
		})
	})

	When("importing an encoded URL", func() {
		It("should bundle decoded URL", func() {
			MockURL("/import-url-module.js", "export default () => { return 'Hello World' };")

			Expect(Build("lib/import_encoded_url.js")).To(ContainCode(`return "Hello World"`))
		})

		It("should error on non-2** response", func() {
			gock.New("https://proscenium.test").
				Get("/import-url-module.js").
				Reply(404)

			result := Build("lib/import_encoded_url.js")

			Expect(result.Errors[0].Text).To(Equal(
				"Fetch of https://proscenium.test/import-url-module.js failed with status code: 404",
			))
		})

		It("should error on reaching max response size", func() {
			originalMaxHttpBodySize := plugin.MaxHttpBodySize
			plugin.MaxHttpBodySize = 2
			defer func() { plugin.MaxHttpBodySize = originalMaxHttpBodySize }()

			MockURL("/import-url-module.js", "hello")

			result := Build("lib/import_encoded_url.js")

			Expect(result.Errors[0].Text).To(Equal(
				"Fetch of https://proscenium.test/import-url-module.js failed: http: request body too large",
			))
		})
	})

	When("importing encoded URL with relative dependency", func() {
		It("should resolve as URL ,encode and not bundle dependency", func() {
			MockURL("/import-url-module.js", `
				import dep from './dependency';
				export default () => { return 'Hello World' + dep };
			`)

			result := Build("lib/import_encoded_url.js")

			Expect(result).To(ContainCode(`return "Hello World"`))
			Expect(result).To(ContainCode(`
				import dep from "/https%3A%2F%2Fproscenium.test%2Fdependency";
			`))
		})

		When("bundling", func() {
			It("should resolve as URL ,encode and not bundle dependency", func() {
				MockURL("/dependency", `export default "dependency"`)
				MockURL("/import-url-module.js", `
					import dep from './dependency';
					export default () => { return 'Hello World' + dep };
				`)

				result := Build("lib/import_encoded_url.js", BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`return "Hello World" + dependency_default`))
				Expect(result).To(ContainCode(`= "dependency";`))
			})
		})
	})

	When("importing encoded URL with URL dependency", func() {
		It("should encode and not bundle dependency", func() {
			MockURL("/import-url-module.js", `
				import dep from 'https://some.url/dependency';
				export default () => { return 'Hello World' + dep };
			`)

			result := Build("lib/import_encoded_url.js")

			Expect(result).To(ContainCode(`return "Hello World`))
			Expect(result).To(ContainCode(`
				import dep from "/https%3A%2F%2Fsome.url%2Fdependency";
			`))
		})

		When("bundling", func() {
			It("should encode and not bundle dependency", func() {
				MockURL("/import-url-module.js", `
					import dep from 'https://some.url/dependency';
					export default () => { return 'Hello World' + dep };
				`)

				result := Build("lib/import_encoded_url.js", BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`return "Hello World`))
				Expect(result).To(ContainCode(`import dep from "/https%3A%2F%2Fsome.url%2Fdependency";`))
			})
		})
	})

	When("importing encoded URL with bare dependency", func() {
		It("should pass through as is", func() {
			MockURL("/import-url-module.js", `
				import { one } from 'mypackage/treeshake';
				export default () => { return 'Hello World' + one };
			`)

			result := Build("lib/import_encoded_url.js")

			Expect(result).To(ContainCode(`return "Hello World" + one`))
			Expect(result).To(ContainCode(`import { one } from "/packages/mypackage/treeshake.js";`))
		})

		When("bundling", func() {
			It("should bundle", func() {
				MockURL("/import-url-module.js", `
					import { one } from 'mypackage/treeshake';
					export default () => { return 'Hello World' + one };
				`)

				result := Build("lib/import_encoded_url.js", BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`return "Hello World" + one`))
				Expect(result).To(ContainCode(`console.log("one");`))
			})
		})
	})
})
