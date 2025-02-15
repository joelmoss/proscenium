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
			result := b.Build("lib/rubygems/index.js")

			Expect(result.Errors[0].Text).To(ContainSubstring("Could not resolve Ruby gem \"gem1\""))
		})
	})

	When("bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
			addGem("gem1")
		})

		It("should resolve to installed ruby gem", func() {
			Expect(b.Build("lib/rubygems/index.js")).To(ContainCode(`
				console.log("gem1");
			`))
		})

		// FIt("should resolve entry point", func() {
		// 	Expect(b.Build("@rubygems/gem1/lib/gem1/gem1.js")).To(ContainCode(`
		// 		console.log("gem1");
		// 	`))
		// })

		Describe("unbundle:*", func() {
			It("should unbundle import", func() {
				Expect(b.Build("lib/rubygems/unbundle.js")).To(ContainCode(`
					import "/vendor/gem1/lib/gem1/gem1.js";
				`))
			})
		})

		Describe("unbundle:* in import map", func() {
			It("should unbundle", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": {
						"@rubygems/gem1/": "unbundle:@rubygems/gem1/"
					}
				}`))

				Expect(b.Build("lib/rubygems/index.js")).To(ContainCode(`
					import "/vendor/gem1/lib/gem1/gem1.js";
				`))
			})
		})
	})

	When("bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
			addGem("gem1")
		})

		It("should resolve to installed ruby gem", func() {
			Expect(b.Build("lib/rubygems/index.js")).To(ContainCode(`
				import "/vendor/gem1/lib/gem1/gem1.js";
			`))
		})
	})
})

func addGem(name string) {
	if types.Config.RubyGems == nil {
		types.Config.RubyGems = map[string]string{}
	}

	types.Config.RubyGems[name] = filepath.Join(fixturesRoot, "dummy", "vendor", name)
}
