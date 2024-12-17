package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.Build(css)", func() {
	Describe("plain css", func() {
		It("should build", func() {
			Expect(b.Build("lib/foo.css")).To(ContainCode(`.body { color: red; }`))
		})
	})

	Describe("css module", func() {
		path := "lib/css_modules/basic.module.css"

		It("should build", func() {
			Expect(b.Build(path)).To(ContainCode(`.foo-c3f452b4 { color: red; }`))
		})
	})

	When("importing absolute path", func() {
		It("should bundle", func() {
			Expect(b.Build("lib/import_absolute.css")).To(ContainCode(`.stuff { color: red; }`))
		})
	})

	When("importing css module from css", func() {
		It("should bundle", func() {
			Expect(b.Build("lib/css_modules/import_css_module.css")).To(ContainCode(`
			/* lib/css_modules/basic.module.css */
			.foo-c3f452b4 { color: red; }
			/* lib/css_modules/import_css_module.css */
			.bar { color: blue; }
			`))
		})
	})

	When("importing css module from css module", func() {
		It("should bundle with different digest", func() {
			result := b.Build("lib/css_modules/import_css_module.module.css")

			Expect(result).To(ContainCode(`.foo-c3f452b4 { color: red; }`))
			Expect(result).To(ContainCode(`.bar-60bd820c { color: blue; }`))
		})
	})

	When("importing relative path", func() {
		It("should bundle", func() {
			Expect(b.Build("lib/import_relative.css")).To(ContainCode(`
			/* lib/foo.css */
			.body { color: red; }
			/* lib/foo2.css */
			.body { color: blue; }
			`))
		})
	})

	When("importing bare specifier", func() {
		It("is replaced with absolute path", func() {
			result := b.Build("lib/import_npm_module.css")

			Expect(result).To(ContainCode(`.mypackage { color: red; }`))
			Expect(result).NotTo(ContainCode(`@import "mypackage/styles";`))
		})
	})

	When("importing bare specifier with extension", func() {
		It("is replaced with absolute path", func() {
			types.Config.Bundle = false
			result := b.Build("lib/import_npm_module_with_ext.css")

			Expect(result).To(ContainCode(`@import "/packages/mypackage/styles.css"`))
		})
	})

	Describe("mixins", func() {
		When("from URL", func() {
			It("is replaced with defined mixin", func() {
				Expect(b.Build("lib/with_mixin_from_url.css")).To(ContainCode(`
						a { color: red; font-size: 20px; }
					`))
			})
		})

		When("from relative URL", func() {
			It("is replaced with defined mixin", func() {
				Expect(b.Build("lib/with_mixin_from_relative_url.css")).To(ContainCode(`
					a { color: red; font-size: 20px; }
				`))
			})
		})
	})

	// FIt("handles ?", func() {
	// 	Expect(BuildToPath("lib/css_mod_import/tab_a.module.css;lib/css_mod_import/tab_b.module.css")).To(ContainCode(`
	// 		a { color: red; font-size: 20px; }
	// 	`))
	// })

	When("importing css module from js", func() {
		var expectedCode = `
			var existingStyle = document.querySelector("#_330940eb");
			var existingLink = document.querySelector('link[href="/lib/styles.module.css"]');
			var existingOriginalLink = document.querySelector('link[data-original-href="/lib/styles.module.css"]');
			if (!existingStyle && !existingLink && !existingOriginalLink) {
				const e = document.createElement("style");
				e.id = "_330940eb";
				e.dataset.href = "/lib/styles.module.css";
				e.dataset.prosceniumStyle = true;
				e.appendChild(document.createTextNode(String.raw` + "`/* lib/styles.module.css */" + `
			.myClass-330940eb {
        color: pink;
      }` + "`" + `));
				const pStyleEle = document.head.querySelector("[data-proscenium-style]");
				pStyleEle ? document.head.insertBefore(e, pStyleEle) : document.head.appendChild(e);
			}
			var styles_default = new Proxy({}, {
				get(target, prop, receiver) {
					if (prop in target || typeof prop === "symbol") {
						return Reflect.get(target, prop, receiver);
					} else {
						return prop + "-330940eb";
					}
				}
			});
		`

		It("includes stylesheet and proxies class names", func() {
			Expect(b.Build("lib/import_css_module.js")).To(ContainCode(expectedCode))
		})

		It("import relative css module from js", func() {
			Expect(b.Build("lib/import_relative_css_module.js")).To(ContainCode(expectedCode))
		})

		When("Bundle = false", func() {
			BeforeEach(func() {
				types.Config.Bundle = false
			})

			It("import relative css module from js", func() {
				Expect(b.Build("lib/import_relative_css_module.js")).To(ContainCode(expectedCode))
			})

			It("includes stylesheet and proxies class names", func() {
				Expect(b.Build("lib/import_css_module.js")).To(ContainCode(expectedCode))
			})
		})

		When("importing css module from css module", func() {
			It("should bundle with different digest", func() {
				result := b.Build("lib/css_modules/import_css_module.js")

				Expect(result).To(ContainCode(`.foo-c3f452b4 { color: red; }`))
				Expect(result).To(ContainCode(`.bar-60bd820c { color: blue; }`))
			})
		})
	})
})
