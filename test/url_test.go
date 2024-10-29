package proscenium_test

import (
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(url)", func() {
	When("importing a URL", func() {
		It("should leave as is", func() {
			Expect(Build("lib/import_url.js")).To(ContainCode(`
				import myFunction from "https://proscenium.test/import-url-module.js";
			`))
		})
	})

	When("import map resolves to url", func() {
		It("should encode URL", func() {
			result := Build("lib/import_map/bare_specifier.js", BuildOpts{
				ImportMap: `{
					"imports": { "foo": "https://proscenium.test/import-url-module.js" }
				}`,
			})

			Expect(result).To(ContainCode(`
					import foo from "https://proscenium.test/import-url-module.js";
				`))
		})
	})

})
