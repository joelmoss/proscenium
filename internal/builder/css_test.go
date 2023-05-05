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

	It("should build css", func() {
		Expect(Build("lib/foo.css")).To(ContainCode(`.body { color: red; }`))
	})

	When("bundling", func() {
		It("should build css", func() {
			Expect(Build("lib/foo.css", BuildOpts{Bundle: true})).To(ContainCode(`.body { color: red; }`))
		})
	})

	It("should build css module", func() {
		Expect(Build("app/components/phlex/side_load_css_module_view.module.css")).To(ContainCode(`
			.basebd9b41e5 { color: red; }
		`))
	})

	When("bundling", func() {
		It("should build css module", func() {
			Expect(Build("app/components/phlex/side_load_css_module_view.module.css", BuildOpts{Bundle: true})).To(ContainCode(`
				.basebd9b41e5 { color: red; }
			`))
		})
	})

	It("should import absolute path", func() {
		Expect(Build("lib/import_absolute.css")).To(ContainCode(`@import "/config/foo.css";`))
	})

	When("bundling", func() {
		It("should bundle absolute path", func() {
			Expect(Build("lib/import_absolute.css", BuildOpts{Bundle: true})).To(ContainCode(`
				.stuff {
					color: red;
				}
			`))
		})
	})

	It("should import relative path", func() {
		Expect(Build("lib/import_relative.css")).To(ContainCode(`
			@import "/lib/foo.css";
			@import "/lib/foo2.css";
		`))
	})

	When("bundling", func() {
		It("should bundle relative path", func() {
			Expect(Build("lib/import_relative.css", BuildOpts{Bundle: true})).To(ContainCode(`
				/* lib/foo.css */
				.body {
					color: red;
				}

				/* lib/foo2.css */
				.body {
					color: blue;
				}
			`))
		})
	})

	When("importing bare specifier", func() {
		It("is replaced with absolute path", func() {
			Expect(Build("lib/import_npm_module.css")).To(ContainCode(`
				@import "/node_modules/.pnpm/normalize.css@8.0.1/node_modules/normalize.css/normalize.css";
			`))
		})

		When("bundling", func() {
			It("is replaced with absolute path", func() {
				result := Build("lib/import_npm_module.css", BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`
					[hidden] {
            display: none;
          }
				`))

				Expect(result).NotTo(ContainCode(`@import 'normalize.css';`))
				Expect(result).NotTo(ContainCode(`
					@import "/node_modules/.pnpm/normalize.css@8.0.1/node_modules/normalize.css/normalize.css";
				`))
			})
		})
	})

	Describe("mixins", func() {
		When("from URL", func() {
			It("is replaced with defined mixin", func() {
				Expect(Build("lib/with_mixin_from_url.css")).To(ContainCode(`
					a {
						color: red;
						font-size: 20px;
					}
				`))
			})

			When("bundling", func() {
				It("is replaced with defined mixin", func() {
					Expect(Build("lib/with_mixin_from_url.css", BuildOpts{Bundle: true})).To(ContainCode(`
						a {
							color: red;
							font-size: 20px;
						}
					`))
				})
			})
		})

		When("from relative URL", func() {
			It("is replaced with defined mixin", func() {
				Expect(Build("lib/with_mixin_from_relative_url.css")).To(ContainCode(`
					a {
						color: red;
						font-size: 20px;
					}
				`))
			})

			When("bundling", func() {
				It("is replaced with defined mixin", func() {
					Expect(Build("lib/with_mixin_from_relative_url.css", BuildOpts{Bundle: true})).To(ContainCode(`
						a {
							color: red;
							font-size: 20px;
						}
					`))
				})
			})
		})
	})

	When("importing css module from js", func() {
		var expectedCode = `
			var e = document.querySelector("#_330940eb");
			if (!e) {
				e = document.createElement("link");
				e.id = "_330940eb";
				e.rel = "stylesheet";
				e.href = "/lib/styles.module.css";
				document.head.appendChild(e);
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

		When("bundling", func() {
			It("includes stylesheet and proxies class names", func() {
				Expect(Build("lib/import_css_module.js", BuildOpts{Bundle: true})).To(ContainCode(expectedCode))
			})

			It("import relative css module from js", func() {
				Expect(Build("lib/import_relative_css_module.js", BuildOpts{Bundle: true})).To(ContainCode(expectedCode))
			})
		})
	})
})
