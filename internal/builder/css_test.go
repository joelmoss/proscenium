package builder_test

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	. "joelmoss/proscenium/internal/test"
	"joelmoss/proscenium/internal/types"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/css", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		builder.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	It("should build css", func() {
		Expect(Build("lib/foo.css")).To(ContainCode(`
			.body { color: red; }
		`))
	})

	It("should build css module", func() {
		Expect(Build("app/components/phlex/side_load_css_module_view.module.css")).To(ContainCode(`
			.base03b26e31 { color: red; }
		`))
	})

	It("should import absolute path", func() {
		Expect(Build("lib/import_absolute.css")).To(ContainCode(`
			@import "/config/foo.css";
		`))
	})

	It("should import relative path", func() {
		result := Build("lib/import_relative.css")

		Expect(result).To(ContainCode(`
			@import "/lib/foo.css";
			@import "/lib/foo2.css";
		`))
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
		})
	})

	When("importing bare specifier", func() {
		It("is replaced with absolute path", func() {
			Expect(Build("lib/import_npm_module.css")).To(ContainCode(`
				@import "/node_modules/.pnpm/normalize.css@8.0.1/node_modules/normalize.css/normalize.css";
			`))
		})
	})

	It("import css module from js", func() {
		Expect(Build("lib/import_css_module.js")).To(EqualCode(`
			// lib/styles.module.css
			var e = document.querySelector("#_9095c7b8");
			if (!e) {
				e = document.createElement("link");
				e.id = "_9095c7b8";
				e.rel = "stylesheet";
				e.href = "/lib/styles.module.css";
				document.head.appendChild(e);
			}
			var styles_module_default = new Proxy({}, {
				get(target, prop, receiver) {
					if (prop in target || typeof prop === "symbol") {
						return Reflect.get(target, prop, receiver);
					} else {
						return prop + "9095c7b8";
					}
				}
			});

			// lib/import_css_module.js
			console.log(styles_module_default);
		`))
	})

	When("bundling", func() {
		It("import css module from js", func() {
			Expect(Build("lib/import_css_module.js", BuildOpts{Bundle: true})).To(EqualCode(`
			// lib/styles.module.css
			var e = document.querySelector("#_9095c7b8");
			if (!e) {
				e = document.createElement("link");
				e.id = "_9095c7b8";
				e.rel = "stylesheet";
				e.href = "/lib/styles.module.css";
				document.head.appendChild(e);
			}
			var styles_module_default = new Proxy({}, {
				get(target, prop, receiver) {
					if (prop in target || typeof prop === "symbol") {
						return Reflect.get(target, prop, receiver);
					} else {
						return prop + "9095c7b8";
					}
				}
			});

			// lib/import_css_module.js
			console.log(styles_module_default);
		`))
		})
	})
})
