package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"
	"path/filepath"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("@rubygems scoped imports", func() {
	When("gem not found", func() {
		It("should resolve to installed ruby gem", func() {
			result := b.Build("lib/rubygems/vendored.js")

			Expect(result.Errors[0].Text).To(ContainSubstring("Could not resolve Ruby gem \"gem1\""))
		})
	})

	When("bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
		})

		It("should resolve vendored ruby gem", func() {
			addGem("gem1", "dummy/vendor")

			Expect(b.Build("lib/rubygems/vendored.js")).To(ContainCode(`
				console.log("gem1");
			`))
		})

		It("should resolve external ruby gem", func() {
			addGem("gem2", "external")

			Expect(b.Build("lib/rubygems/external.js")).To(ContainCode(`
				console.log("gem2");
			`))
		})

		It("should resolve without extension", func() {
			addGem("gem1", "dummy/vendor")

			Expect(b.Build("lib/rubygems/extensionless.js")).To(ContainCode(`
				console.log("gem1");
			`))
		})

		It("should resolve without filename (index)", func() {
			addGem("gem1", "dummy/vendor")

			Expect(b.Build("lib/rubygems/filenameless.js")).To(ContainCode(`
				console.log("gem1/index.js");
			`))
		})

		// FIt("should resolve entry point", func() {
		// 	Expect(b.Build("@rubygems/gem1/lib/gem1/gem1.js")).To(ContainCode(`
		// 		console.log("gem1");
		// 	`))
		// })

		Describe("unbundle:* vendored gem", func() {
			It("should unbundle import", func() {
				addGem("gem1", "dummy/vendor")

				Expect(b.Build("lib/rubygems/unbundle_vendored.js")).To(ContainCode(`
					import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
				`))
			})
		})

		Describe("unbundle:* external gem", func() {
			It("should unbundle import", func() {
				addGem("gem2", "external")

				Expect(b.Build("lib/rubygems/unbundle_external.js")).To(ContainCode(`
					import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
				`))
			})
		})

		Describe("unbundle:* in import map", func() {
			It("should unbundle", func() {
				addGem("gem1", "dummy/vendor")
				importmap.NewJsonImportMap([]byte(`{
					"imports": {
						"@rubygems/gem1/": "unbundle:@rubygems/gem1/"
					}
				}`))

				Expect(b.Build("lib/rubygems/vendored.js")).To(ContainCode(`
					import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
				`))
			})
		})

		It("should resolve nested imports", func() {
			addGem("gem1", "dummy/vendor")
			addGem("gem2", "external")

			result := b.Build("lib/rubygems/nested_imports.js")

			Expect(result).To(ContainCode(`console.log("gem1");`))
			Expect(result).To(ContainCode(`console.log("gem2");`))
			Expect(result).To(ContainCode(`console.log("node_modules/mypackage");`))
		})
	})

	When("bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
		})

		It("should resolve vendored ruby gem", func() {
			addGem("gem1", "dummy/vendor")

			Expect(b.Build("lib/rubygems/vendored.js")).To(ContainCode(`
				import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
			`))
		})

		It("should resolve external ruby gem", func() {
			addGem("gem2", "external")

			Expect(b.Build("lib/rubygems/external.js")).To(ContainCode(`
				import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
			`))
		})

		It("should resolve without extension", func() {
			addGem("gem1", "dummy/vendor")

			Expect(b.Build("lib/rubygems/extensionless.js")).To(ContainCode(`
				import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
			`))
		})

		It("should resolve without filename (index)", func() {
			addGem("gem1", "dummy/vendor")

			Expect(b.Build("lib/rubygems/filenameless.js")).To(ContainCode(`
				import "/node_modules/@rubygems/gem1/index.js";
			`))
		})
	})
})

func addGem(name string, path string) {
	if types.Config.RubyGems == nil {
		types.Config.RubyGems = map[string]string{}
	}

	types.Config.RubyGems[name] = filepath.Join(fixturesRoot, path, name)
}
