package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.BuildToString(css)", func() {
	It("builds plain css", func() {
		_, result := b.BuildToString("lib/foo.css")

		Expect(result).To(ContainCode(`.body { color: red; }`))
	})

	It("builds css modules", func() {
		_, result := b.BuildToString("lib/css_modules/basic.module.css")

		Expect(result).To(ContainCode(`.foo-c3f452b4 { color: red; }`))
	})

	It("bundles absolute path import", func() {
		_, result := b.BuildToString("lib/import_absolute.css")

		Expect(result).To(ContainCode(`.stuff { color: red; }`))
	})

	It("bundles css module import from css", func() {
		_, result := b.BuildToString("lib/css_modules/import_css_module.css")

		Expect(result).To(ContainCode(`
			/* lib/css_modules/basic.module.css */
			.foo-c3f452b4 { color: red; }
			/* lib/css_modules/import_css_module.css */
			.bar { color: blue; }
		`))
	})

	It("bundles import of css module from css module with different digest", func() {
		_, result := b.BuildToString("lib/css_modules/import_css_module.module.css")

		Expect(result).To(ContainCode(`.foo-c3f452b4 { color: red; }`))
		Expect(result).To(ContainCode(`.bar-60bd820c { color: blue; }`))
	})

	It("bundles relative path import", func() {
		_, result := b.BuildToString("lib/import_relative.css")

		Expect(result).To(ContainCode(`
			/* lib/foo.css */
			.body { color: red; }
			/* lib/foo2.css */
			.body { color: blue; }
		`))
	})

	It("bare specifier import is replaced with absolute path", func() {
		_, result := b.BuildToString("lib/import_npm_module.css")

		Expect(result).To(ContainCode(`.mypackage { color: red; }`))
		Expect(result).NotTo(ContainCode(`@import "mypackage/styles";`))
	})

	It("bare specifier import with extension is replaced with absolute path", func() {
		types.Config.Bundle = false
		_, result := b.BuildToString("lib/import_npm_module_with_ext.css")

		Expect(result).To(ContainCode(`@import "/packages/mypackage/styles.css"`))
	})

	Describe("mixins", func() {
		It("URL is replaced with defined mixin", func() {
			_, result := b.BuildToString("lib/with_mixin_from_url.css")

			Expect(result).To(ContainCode(`
				a { color: red; font-size: 20px; }
			`))
		})

		It("relative URL is replaced with defined mixin", func() {
			_, result := b.BuildToString("lib/with_mixin_from_relative_url.css")

			Expect(result).To(ContainCode(`
				a { color: red; font-size: 20px; }
			`))
		})

		Context("internal @rubygems/*", func() {
			It("replaces relative URL with defined mixin", func() {
				addGem("gem3", "dummy/vendor")

				_, result := b.BuildToString("node_modules/@rubygems/gem3/lib/gem3/styles.module.css")

				Expect(result).To(ContainCode(`h1 { color: red; }`))
			})
		})

		Context("external @rubygems/*", func() {
			It("replaces relative URL with defined mixin", func() {
				addGem("gem4", "external")

				_, result := b.BuildToString("node_modules/@rubygems/gem4/lib/gem4/styles.module.css")

				Expect(result).To(ContainCode(`h1 { color: red; }`))
			})
		})
	})

	// FIt("handles ?", func() {
	// 	Expect(BuildToStringToPath("lib/css_mod_import/tab_a.module.css;lib/css_mod_import/tab_b.module.css")).To(ContainCode(`
	// 		a { color: red; font-size: 20px; }
	// 	`))
	// })

	When("importing css module from js", func() {
		var expectedCode = `
			var u = "/lib/styles.module.css";
			var es = document.querySelector("#_330940eb");
			var el = document.querySelector('link[href="' + u + '"]');
			var eo = document.querySelector('link[data-original-href="' + u + '"]');
			if (!es && !el && !eo) {
				const e = document.createElement("style");
				e.id = "_330940eb";
				e.dataset.href = u;
				e.dataset.prosceniumStyle = true;
				e.appendChild(document.createTextNode(String.raw` + "`/* lib/styles.module.css */" + `
			.myClass-330940eb {
        color: pink;
      }` + "`" + `));
				const ps = document.head.querySelector("[data-proscenium-style]");
				ps ? document.head.insertBefore(e, ps) : document.head.appendChild(e);
			}
			var styles_default = new Proxy({}, {
				get(t, p, r) {
					return p in t || typeof p === "symbol" ? Reflect.get(t, p, r) : p + "-330940eb";
				}
			});
		`

		When("Bundle = true", func() {
			BeforeEach(func() {
				types.Config.Bundle = true
			})

			It("includes stylesheet and proxies class names", func() {
				_, result := b.BuildToString("lib/import_css_module.js")

				Expect(result).To(ContainCode(expectedCode))
			})

			It("import relative css module from js", func() {
				_, result := b.BuildToString("lib/import_relative_css_module.js")

				Expect(result).To(ContainCode(expectedCode))
			})
		})

		When("Bundle = false", func() {
			BeforeEach(func() {
				types.Config.Bundle = false
			})

			It("import relative css module from js", func() {
				_, result := b.BuildToString("lib/import_relative_css_module.js")

				Expect(result).To(ContainCode(`import styles from "/lib/styles.module.css";`))
			})

			It("includes stylesheet and proxies class names", func() {
				_, result := b.BuildToString("lib/import_css_module.js")

				Expect(result).To(ContainCode(`import styles from "/lib/styles.module.css";`))
			})
		})

		When("importing css module from css module", func() {
			It("should bundle with different digest", func() {
				_, result := b.BuildToString("lib/css_modules/import_css_module.js")

				Expect(result).To(ContainCode(`.foo-c3f452b4 { color: red; }`))
				Expect(result).To(ContainCode(`.bar-60bd820c { color: blue; }`))
			})
		})

		Context("internal @rubygems/*", func() {
			BeforeEach(func() {
				addGem("gem1", "dummy/vendor")
			})

			It("includes stylesheet and proxies class names", func() {
				_, result := b.BuildToString("lib/rubygems/internal_import_css_module.js")

				Expect(result).To(ContainCode(`var u = "/node_modules/@rubygems/gem1/styles.module.css";`))
				Expect(result).To(ContainCode(`var es = document.querySelector("#_3f751f91");`))
				Expect(result).To(ContainCode(`.myClass-3f751f91 { color: pink; }`))
			})
		})

		Context("external @rubygems/*", func() {
			BeforeEach(func() {
				addGem("gem2", "external")
			})

			It("includes stylesheet and proxies class names", func() {
				_, result := b.BuildToString("lib/rubygems/external_import_css_module.js")

				Expect(result).To(ContainCode(`var u = "/node_modules/@rubygems/gem2/styles.module.css";`))
				Expect(result).To(ContainCode(`var es = document.querySelector("#_e789966c");`))
				Expect(result).To(ContainCode(`.myClass-e789966c { color: pink; }`))
			})
		})
	})
})
