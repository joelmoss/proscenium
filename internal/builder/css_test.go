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

var _ = Describe("Internal/Builder.Build/css", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		plugin.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	Describe("plain css", func() {
		path := "lib/foo.css"

		It("should build", func() {
			Expect(Build(path)).To(ContainCode(`.body { color: red; }`))
		})

		When("bundling", func() {
			It("should build", func() {
				Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`.body { color: red; }`))
			})
		})
	})

	Describe("css module", func() {
		path := "app/components/phlex/side_load_css_module_view.module.css"

		It("should build", func() {
			Expect(Build(path)).To(ContainCode(`.basebd9b41e5 { color: red; }`))
		})

		When("bundling", func() {
			It("should build", func() {
				Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`.basebd9b41e5 { color: red; }`))
			})
		})
	})

	When("importing absolute path", func() {
		path := "lib/import_absolute.css"

		It("should pass through as is", func() {
			Expect(Build(path)).To(ContainCode(`@import "/config/foo.css";`))
		})

		When("bundling", func() {
			It("should bundle", func() {
				Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`.stuff { color: red; }`))
			})
		})
	})

	When("importing css module from css", func() {
		path := "lib/css_modules/import_css_module.css"

		When("bundling", func() {
			It("should bundle", func() {
				Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`
					/* lib/css_modules/basic.module.css */
          .fooc3f452b4 { color: red; }
          /* lib/css_modules/import_css_module.css */
          .bar { color: blue; }
				`))
			})
		})
	})

	When("importing css module from css module", func() {
		path := "lib/css_modules/import_css_module.module.css"

		When("bundling", func() {
			It("should bundle with same digest", func() {
				Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`.foo60bd820c { color: red; }`))
				Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`.bar60bd820c { color: blue; }`))
			})
		})
	})

	When("importing relative path", func() {
		path := "lib/import_relative.css"

		It("should resolve paths unbundled", func() {
			Expect(Build(path)).To(ContainCode(`
				@import "/lib/foo.css";
				@import "/lib/foo2.css";
			`))
		})

		When("bundling", func() {
			It("should bundle", func() {
				Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`
					/* lib/foo.css */
					.body { color: red; }
					/* lib/foo2.css */
					.body { color: blue; }
				`))
			})
		})
	})

	When("importing bare specifier", func() {
		path := "lib/import_npm_module.css"

		It("is replaced with absolute path", func() {
			Expect(Build(path)).To(ContainCode(`
				@import "/node_modules/.pnpm/normalize.css@8.0.1/node_modules/normalize.css/normalize.css";
			`))
		})

		When("bundling", func() {
			It("is replaced with absolute path", func() {
				result := Build(path, BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`[hidden] { display: none; }`))
				Expect(result).NotTo(ContainCode(`@import 'normalize.css';`))
				Expect(result).NotTo(ContainCode(`
					@import "/node_modules/.pnpm/normalize.css@8.0.1/node_modules/normalize.css/normalize.css";
				`))
			})
		})
	})

	Describe("mixins", func() {
		When("from URL", func() {
			path := "lib/with_mixin_from_url.css"

			It("is replaced with defined mixin", func() {
				Expect(Build(path)).To(ContainCode(`a { color: red; font-size: 20px; }`))
			})

			When("bundling", func() {
				It("is replaced with defined mixin", func() {
					Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`
						a { color: red; font-size: 20px; }
					`))
				})
			})
		})

		When("from relative URL", func() {
			path := "lib/with_mixin_from_relative_url.css"

			It("is replaced with defined mixin", func() {
				Expect(Build(path)).To(ContainCode(`a {	color: red;	font-size: 20px; }`))
			})

			When("bundling", func() {
				It("is replaced with defined mixin", func() {
					Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`a { color: red; font-size: 20px; }`))
				})
			})
		})
	})

	When("importing css module from js", func() {
		css := "`.myClass330940eb{color:pink}`"
		var expectedCode = `
			var existingStyle = document.querySelector("#_330940eb");
			var existingLink = document.querySelector('link[href="/lib/styles.module.css"]');
			if (!existingStyle && !existingLink) {
				const e = document.createElement("style");
				e.id = "_330940eb";
				e.dataset.href = "/lib/styles.module.css";
				e.appendChild(document.createTextNode(` + css + `));
				document.head.insertBefore(e, document.querySelector("style"));
			}
			var styles_module_default = new Proxy({}, {
				get(target, prop, receiver) {
					if (prop in target || typeof prop === "symbol") {
						return Reflect.get(target, prop, receiver);
					} else {
						return prop + "330940eb";
					}
				}
			});
		`

		It("includes stylesheet and proxies class names", func() {
			Expect(Build("lib/import_css_module.js")).To(ContainCode(expectedCode))
		})

		When("invalid css", func() {
			It("returns error", func() {
				result := Build("lib/import_invalid_css_module.js")

				Expect(result.Errors[0].Text).To(Equal("Could not resolve \"lib/invalid.module.css\""))
			})
		})

		When("bundling", func() {
			It("includes stylesheet and proxied class names", func() {
				Expect(Build("lib/import_css_module.js", BuildOpts{Bundle: true})).To(ContainCode(expectedCode))
			})

			It("import relative css module from js", func() {
				Expect(Build("lib/import_relative_css_module.js", BuildOpts{Bundle: true})).To(ContainCode(expectedCode))
			})

			When("importing css module from css module", func() {
				path := "lib/css_modules/import_css_module.js"

				When("bundling", func() {
					It("should bundle with same digest", func() {
						Expect(Build(path, BuildOpts{Bundle: true})).To(ContainCode(`
							.foo60bd820c{color:red}.bar60bd820c{color:#00f}
						`))
					})
				})
			})
		})
	})
})
