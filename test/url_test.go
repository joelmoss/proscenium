package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.Build(url)", func() {
	When("importing a URL", func() {
		It("should leave as is", func() {
			Expect(b.Build("lib/import_url.js")).To(ContainCode(`
			import myFunction from "https://proscenium.test/import-url-module.js";
			`))
		})
	})

	When("import map resolves to url", func() {
		It("should encode URL", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "foo": "https://proscenium.test/import-url-module.js" }
			}`))

			Expect(b.Build("lib/import_map/bare_specifier.js")).To(ContainCode(`
				import foo from "https://proscenium.test/import-url-module.js";
			`))
		})
	})
})
