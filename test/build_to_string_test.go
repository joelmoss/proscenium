package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var behavesLikeBuildToString = func() {
	It("builds js", func() {
		_, result := b.BuildToString("lib/foo.js")

		Expect(result).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("builds css", func() {
		_, result := b.BuildToString("lib/foo.css")

		Expect(result).To(ContainCode(`.body { color: red; }`))
	})

	It("leaves rjs imports untouched", func() {
		_, code := b.BuildToString("lib/rjs.js")

		Expect(code).To(ContainCode(`import foo from "/constants.rjs"`))
	})

	It("does not bundle fonts", func() {
		_, code := b.BuildToString("lib/fonts.css")

		Expect(code).To(ContainCode(`url(/somefont.woff2)`))
		Expect(code).To(ContainCode(`url(/somefont.woff)`))
	})

	It("should leave URLs as is", func() {
		_, code := b.BuildToString("lib/import_url.js")

		Expect(code).To(ContainCode(`
			import myFunction from "https://proscenium.test/import-url-module.js";
		`))
	})

	Describe("proscenium.env.* variables", func() {
		It("replaces ENV vars", func() {
			_, code := b.BuildToString("lib/env/env.js")

			Expect(code).To(ContainCode(`console.log("testtest");`))
		})

		When("env var is undefined", func() {
			It("is void", func() {
				_, code := b.BuildToString("lib/env/unknown.js")

				Expect(code).To(ContainCode(`
					console.log((void 0).NUFFIN);
					console.log("test");
				`))
			})
		})
	})

	Describe("source maps", func() {
		It("returns source map", func() {
			_, result := b.BuildToString("lib/foo.js.map")

			Expect(result).To(ContainCode(`
				"sources": ["../../../lib/foo.js"],
				"sourcesContent": ["console.log('/lib/foo.js')\n"],
			`))
		})

		It("appends source map location for js", func() {
			_, result := b.BuildToString("lib/foo.js")

			Expect(result).To(ContainCode("//# sourceMappingURL=foo.js.map"))
		})

		It("appends source map location for css", func() {
			_, result := b.BuildToString("lib/foo.css")

			Expect(result).To(ContainCode("/*# sourceMappingURL=foo.css.map */"))
		})
	})
}

var _ = Describe("BuildToString", func() {
	Describe("bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
		})

		assertCommonBuildBehaviour(b.BuildToString)
		behavesLikeBuildToString()

		It("bundles bare module without extension", func() {
			_, result := b.BuildToString("lib/import_npm_module.js")

			Expect(result).To(ContainCode(`
				function one() { console.log("one"); }
			`))
		})

		It("bundles bare module with extension", func() {
			_, result := b.BuildToString("lib/import_npm_module_with_ext.js")

			Expect(result).To(ContainCode(`
				console.log("node_modules/mypackage");
			`))
		})

		It("resolves extension-less imports", func() {
			_, result := b.BuildToString("lib/import_absolute_module_without_extension.js")

			Expect(result).To(ContainCode(`
				console.log("/lib/foo2.js")
			`))
		})

		It("bundles relative path", func() {
			_, result := b.BuildToString("lib/import_relative_module.js")

			Expect(result).To(ContainCode(`
				console.log("/lib/foo4.js")
			`))
		})

		It("bundles extension-less relative path", func() {
			_, code := b.BuildToString("lib/import_relative_module_without_extension.js")

			Expect(code).To(ContainCode(`
				console.log("/lib/foo4.js")
			`))
		})

		It("bundles absolute path", func() {
			_, result := b.BuildToString("lib/import_absolute_module.js")

			Expect(result).To(ContainCode(`
				console.log("/lib/foo4.js")
			`))
		})

		Describe("unbundle:* imports", func() {
			It("unbundles imports", func() {
				importmap.NewJsonImportMap([]byte(`{
					"imports": {
						"/lib/foo3.js": "unbundle:/lib/foo3.js",
						"react-dom": "unbundle:react-dom"
					}
				}`))

				_, result := b.BuildToString("lib/unbundle/local_modules.js")

				Expect(result).To(ContainCode(`
					import "/lib/unbundle/foo1.js";
					import "/lib/unbundle/foo2.js";
					import "/lib/foo3.js";
					import { one } from "/packages/mypackage/treeshake.js";
					// packages/mypackage/index.js
					console.log("node_modules/mypackage");
				`))
			})
		})

		It("tree shakes bare import", func() {
			_, code := b.BuildToString("lib/import_tree_shake.js")

			Expect(code).To(ContainCode(`
				// packages/mypackage/treeshake.js
				function one() {
					console.log("one");
				}

				// lib/import_tree_shake.js
				one();
			`))
		})

		When("css", func() {
			It("bundles absolute path", func() {
				_, code := b.BuildToString("lib/import_absolute.css")

				Expect(code).To(ContainCode(`
					.stuff {
						color: red;
					}
				`))
			})

			It("bundles relative path", func() {
				_, code := b.BuildToString("lib/import_relative.css")

				Expect(code).To(ContainCode(`
					.body {
						color: red;
					}
				`))
				Expect(code).To(ContainCode(`
					.body {
						color: blue;
					}
				`))
			})
		})
	})

	Describe("bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
		})

		assertCommonBuildBehaviour(b.BuildToString)
		behavesLikeBuildToString()

		It("does not build entrypoint with import map", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": {
					"/lib/foo.js": "/lib/foo2.js"
				}
			}`))
			_, code := b.BuildToString("lib/foo.js")

			Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
		})

		It("resolves bare module", func() {
			_, code := b.BuildToString("lib/import_npm_module.js")

			Expect(code).To(ContainCode(`
				import { one } from "/packages/mypackage/treeshake.js";
				one();
			`))
		})

		It("resolves extension-less imports", func() {
			_, code := b.BuildToString("lib/import_absolute_module_without_extension.js")

			Expect(code).To(ContainCode(`
				import foo from "/lib/foo2.js";
			`))
		})

		It("resolves relative path", func() {
			_, code := b.BuildToString("lib/import_relative_module.js")

			Expect(code).To(ContainCode(`
				import foo4 from "/lib/foo4.js";
				foo4();
			`))
		})

		It("resolves absolute path", func() {
			_, code := b.BuildToString("lib/import_absolute_module.js")

			Expect(code).To(ContainCode(`
				import foo4 from "/lib/foo4.js";
				foo4();
			`))
		})

		It("should resolve from import map", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": {
					"/lib/foo4.js": "/lib/foo.js"
				}
			}`))

			_, code := b.BuildToString("lib/import_absolute_module.js")

			Expect(code).To(ContainCode(`
				import foo4 from "/lib/foo.js";
				foo4();
			`))
		})

		It("unbundle: prefix is stripped and ignored", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": {
					"/lib/foo3.js": "unbundle:/lib/foo32.js",
					"react-dom": "unbundle:react-dom"
				}
			}`))

			_, code := b.BuildToString("lib/unbundle/local_modules.js")

			Expect(code).To(ContainCode(`
				import "/lib/unbundle/foo1.js";
				import "/lib/unbundle/foo2.js";
				import "/lib/foo32.js";
				import { one } from "/packages/mypackage/treeshake.js";
				import "/packages/mypackage/index.js";
			`))
		})
	})
})

func BenchmarkBuildToString(bm *testing.B) {
	bm.ResetTimer()

	for i := 0; i < bm.N; i++ {
		success, result := b.BuildToString("lib/foo.js")

		if !success {
			panic("Build failed: " + result)
		}
	}
}
