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

var _ = Describe("@rubygems scoped paths", func() {
	Context("entrypoint", func() {
		It("fails if gem not found", func() {
			success, result := b.BuildToString("node_modules/@rubygems/gem1/lib/gem1/gem1.js")

			Expect(success).To(BeFalse())
			Expect(result).To(ContainSubstring(`Could not resolve Ruby gem \"gem1\"`))
		})
	})

	Context("import", func() {
		It("fails if gem not found", func() {
			success, result := b.BuildToString("lib/rubygems/vendored.js")

			Expect(success).To(BeFalse())
			Expect(result).To(ContainSubstring(`Could not resolve Ruby gem \"gem1\"`))
		})
	})

	When("bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
		})

		Describe("inside root", func() {
			BeforeEach(func() {
				addGem("gem1", "dummy/vendor")
			})

			It("bundles", func() {
				_, code := b.BuildToString("lib/rubygems/vendored.js")

				Expect(code).To(ContainCode(`
					console.log("gem1");
				`))
			})

			It("bundles without extension", func() {
				_, code := b.BuildToString("lib/rubygems/vendored_extensionless.js")

				Expect(code).To(ContainCode(`
					console.log("gem1");
				`))
			})

			It("resolves entry point", func() {
				_, code := b.BuildToString("node_modules/@rubygems/gem1/lib/gem1/gem1.js")

				Expect(code).To(ContainCode(`
					console.log("gem1");
				`))
			})

			It("bundles from entrypoint", func() {
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code := b.BuildToString("node_modules/@rubygems/gem3/lib/gem3/gem3.js")

				Expect(code).To(ContainCode(`function one() { console.log("one"); }`))
				Expect(code).To(ContainCode(`console.log("gem3/imported")`))
				Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
				Expect(code).To(ContainCode(`console.log("gem3/foo")`))
				Expect(code).To(ContainCode(`console.log("gem3")`))
				Expect(code).To(ContainCode(`console.log("gem1")`))
				Expect(code).To(ContainCode(`console.log("gem4")`))
				Expect(code).To(ContainCode(`h1 { color: red; }`))
				Expect(code).To(ContainCode(`h2 { color: blue; }`))
				Expect(code).To(ContainCode(`h3 { color: green; }`))
				Expect(code).To(ContainCode(`console.log("lib/gem3/gem3")`))
			})

			It("bundles from import", func() {
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code := b.BuildToString("lib/gems/gem3.js")

				Expect(code).To(ContainCode(`function one() { console.log("one"); }`))
				Expect(code).To(ContainCode(`console.log("gem3/imported")`))
				Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
				Expect(code).To(ContainCode(`console.log("gem3/foo")`))
				Expect(code).To(ContainCode(`console.log("gem3")`))
				Expect(code).To(ContainCode(`console.log("gem1")`))
				Expect(code).To(ContainCode(`console.log("gem4")`))
				Expect(code).To(ContainCode(`h1 { color: red; }`))
				Expect(code).To(ContainCode(`h2 { color: blue; }`))
				Expect(code).To(ContainCode(`h3 { color: green; }`))
				Expect(code).To(ContainCode(`console.log("lib/gem3/gem3")`))
			})

			When("unbundle:* on import", func() {
				It("unbundles", func() {
					_, code := b.BuildToString("lib/rubygems/unbundle_vendored.js")

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
					`))
				})
			})

			When("unbundle:* in import map", func() {
				It("unbundles", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": {
							"@rubygems/gem1/": "unbundle:@rubygems/gem1/"
						}
					}`))

					_, code := b.BuildToString("lib/rubygems/vendored.js")

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
					`))
				})
			})

			It("does not bundle fonts", func() {
				_, code := b.BuildToString("lib/rubygems/internal_fonts.css")

				Expect(code).To(ContainCode(`url(/node_modules/@rubygems/gem1/somefont.woff2)`))
			})
		})

		Describe("outside root", func() {
			BeforeEach(func() {
				addGem("gem2", "external")
			})

			It("bundles", func() {
				_, code := b.BuildToString("lib/rubygems/external.js")

				Expect(code).To(ContainCode(`
					console.log("gem2");
				`))
			})

			It("bundles without extension", func() {
				_, code := b.BuildToString("lib/rubygems/external_extensionless.js")

				Expect(code).To(ContainCode(`
					console.log("gem2");
				`))
			})

			It("resolves entry point", func() {
				_, code := b.BuildToString("node_modules/@rubygems/gem2/lib/gem2/gem2.js")

				Expect(code).To(ContainCode(`
					console.log("gem2");
				`))
			})

			It("bundles from entrypoint", func() {
				addGem("gem1", "dummy/vendor")
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code := b.BuildToString("node_modules/@rubygems/gem4/lib/gem4/gem4.js")

				Expect(code).To(ContainCode(`document.querySelector("#_3ddf717c")`))
				Expect(code).To(ContainCode(`e.id = "_3ddf717c";`))
				Expect(code).To(ContainCode(`.name-3ddf717c`))

				Expect(code).To(ContainCode(`function one() { console.log("one"); }`))
				Expect(code).To(ContainCode(`console.log("gem4/imported")`))
				Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
				Expect(code).To(ContainCode(`console.log("gem4/foo")`))
				Expect(code).To(ContainCode(`console.log("gem4")`))
				Expect(code).To(ContainCode(`console.log("gem3")`))
				Expect(code).To(ContainCode(`console.log("gem2")`))
				Expect(code).To(ContainCode(`h1 { color: red; }`))
				Expect(code).To(ContainCode(`h2 { color: blue; }`))
				Expect(code).To(ContainCode(`h3 { color: green; }`))
				Expect(code).To(ContainCode(`console.log("lib/gem4/gem4")`))
			})

			It("bundles from import", func() {
				addGem("gem1", "dummy/vendor")
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code := b.BuildToString("lib/gems/gem4.js")

				Expect(code).To(ContainCode(`document.querySelector("#_3ddf717c")`))
				Expect(code).To(ContainCode(`e.id = "_3ddf717c";`))
				Expect(code).To(ContainCode(`.name-3ddf717c`))

				Expect(code).To(ContainCode(`function one() { console.log("one"); }`))
				Expect(code).To(ContainCode(`console.log("gem4/imported")`))
				Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
				Expect(code).To(ContainCode(`console.log("gem4/foo")`))
				Expect(code).To(ContainCode(`console.log("gem4")`))
				Expect(code).To(ContainCode(`console.log("gem3")`))
				Expect(code).To(ContainCode(`console.log("gem2")`))
				Expect(code).To(ContainCode(`h1 { color: red; }`))
				Expect(code).To(ContainCode(`h2 { color: blue; }`))
				Expect(code).To(ContainCode(`h3 { color: green; }`))
				Expect(code).To(ContainCode(`console.log("lib/gem4/gem4")`))
			})

			When("unbundle:* on import", func() {
				It("unbundles", func() {
					_, code := b.BuildToString("lib/rubygems/unbundle_external.js")

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
					`))
				})
			})

			Describe("unbundle:* in import map", func() {
				It("unbundles", func() {
					importmap.NewJsonImportMap([]byte(`{
						"imports": {
							"@rubygems/gem2/": "unbundle:@rubygems/gem2/"
						}
					}`))

					_, code := b.BuildToString("lib/rubygems/external.js")

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
					`))
				})
			})

			It("does not bundle fonts", func() {
				_, code := b.BuildToString("lib/rubygems/external_fonts.css")

				Expect(code).To(ContainCode(`url(/node_modules/@rubygems/gem2/somefont.woff2)`))
			})
		})
	})

	When("bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
		})

		Describe("inside root", func() {
			BeforeEach(func() {
				addGem("gem1", "dummy/vendor")
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")
			})

			It("bundles", func() {
				_, code := b.BuildToString("lib/rubygems/vendored.js")

				Expect(code).To(ContainCode(`
					import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
				`))
			})

			It("bundles without extension", func() {
				_, code := b.BuildToString("lib/rubygems/vendored_extensionless.js")

				Expect(code).To(ContainCode(`
					import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
				`))
			})

			It("resolves entry point", func() {
				_, code := b.BuildToString("node_modules/@rubygems/gem1/lib/gem1/gem1.js")

				Expect(code).To(ContainCode(`
					console.log("gem1");
				`))
			})

			It("rubygem is resolved before import map", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": {
						"@rubygems/gem3/lib/gem3/console.js": "/lib/foo.js",
					}
				}`))

				_, code := b.BuildToString("lib/rubygems/gem3.js")

				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem3/lib/gem3/console.js";`))
			})

			It("resolves imports", func() {
				_, code := b.BuildToString("node_modules/@rubygems/gem3/lib/gem3/gem3.js")

				Expect(code).To(ContainCode(`import { one } from "/packages/mypackage/treeshake.js";`))
				Expect(code).To(ContainCode(`import imported from "/node_modules/@rubygems/gem3/lib/gem3/imported.js";`))
				Expect(code).To(ContainCode(`import "/lib/foo.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem3/lib/gem3/foo.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem3/lib/gem3/console.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem1/lib/gem1/console.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem4/lib/gem4/console.js";`))
				Expect(code).To(ContainCode(`import styles from "/node_modules/@rubygems/gem3/lib/gem3/styles.module.css";`))
				Expect(code).To(ContainCode(`console.log("lib/gem3/gem3")`))
			})

			It("does not bundle fonts", func() {
				_, code := b.BuildToString("lib/rubygems/internal_fonts.css")

				Expect(code).To(ContainCode(`url(/node_modules/@rubygems/gem1/somefont.woff2)`))
			})
		})

		Describe("outside root", func() {
			BeforeEach(func() {
				addGem("gem2", "external")
			})

			It("bundles", func() {
				_, code := b.BuildToString("lib/rubygems/external.js")

				Expect(code).To(ContainCode(`
					import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
				`))
			})

			It("bundles without extension", func() {
				_, code := b.BuildToString("lib/rubygems/external_extensionless.js")

				Expect(code).To(ContainCode(`
					import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
				`))
			})

			It("resolves entry point", func() {
				_, code := b.BuildToString("node_modules/@rubygems/gem2/lib/gem2/gem2.js")

				Expect(code).To(ContainCode(`
					console.log("gem2");
				`))
			})

			It("rubygem is resolved before import map", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": {
						"@rubygems/gem2/lib/gem2/console.js": "/lib/foo.js",
					}
				}`))

				_, code := b.BuildToString("lib/rubygems/gem2.js")

				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem2/lib/gem2/console.js";`))
			})

			It("resolves import", func() {
				addGem("gem1", "dummy/vendor")
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code := b.BuildToString("node_modules/@rubygems/gem4/lib/gem4/gem4.js")

				Expect(code).To(ContainCode(`import { one } from "/packages/mypackage/treeshake.js";`))
				Expect(code).To(ContainCode(`import imported from "/node_modules/@rubygems/gem4/lib/gem4/imported.js";`))
				Expect(code).To(ContainCode(`import "/lib/foo.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem4/lib/gem4/foo.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem4/lib/gem4/console.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem3/lib/gem3/console.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem2/lib/gem2/console.js";`))
				Expect(code).To(ContainCode(`import styles from "/node_modules/@rubygems/gem4/lib/gem4/styles.module.css";`))
				Expect(code).To(ContainCode(`console.log("lib/gem4/gem4")`))
			})

			It("does not bundle fonts", func() {
				_, code := b.BuildToString("lib/rubygems/external_fonts.css")

				Expect(code).To(ContainCode(`url(/node_modules/@rubygems/gem2/somefont.woff2)`))
			})
		})
	})
})

func addGem(name string, path string) {
	if types.Config.RubyGems == nil {
		types.Config.RubyGems = map[string]string{}
	}

	types.Config.RubyGems[name] = filepath.Join(fixturesRoot, path, name)
}
