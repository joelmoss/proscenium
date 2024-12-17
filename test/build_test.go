package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"
	"os"
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var cwd, _ = os.Getwd()
var fixturesRoot string = filepath.Join(cwd, "..", "fixtures")

var _ = Describe("Build", func() {
	It("should fail on unknown entrypoint", func() {
		result := b.Build("unknown.js")

		Expect(result.Errors[0].Text).To(Equal("Could not resolve \"unknown.js\""))
	})

	It("should build js", func() {
		Expect(b.Build("lib/foo.js")).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("should bundle rjs", Pending, func() {
		MockURL("/constants.rjs", "export default 'constants';")

		Expect(b.Build("lib/rjs.js")).To(ContainCode(`"constants"`))
	})

	It("should bundle bare module", func() {
		Expect(b.Build("lib/import_npm_module.js")).To(ContainCode(`
			function one() { console.log("one"); }
		`))
	})

	It("should resolve extension-less imports", func() {
		Expect(b.Build("lib/import_absolute_module_without_extension.js")).To(ContainCode(`
			console.log("/lib/foo2.js")
		`))
	})

	It("should bundle relative path", func() {
		Expect(b.Build("lib/import_relative_module.js")).To(ContainCode(`
			console.log("/lib/foo4.js")
		`))
	})

	It("should bundle absolute path", func() {
		Expect(b.Build("lib/import_absolute_module.js")).To(ContainCode(`
			console.log("/lib/foo4.js")
		`))
	})

	PIt("should build dynamic path", func() {
		Expect(b.Build("lib/import_dynamic.js")).To(ContainCode(`
			console.log("/lib/foo4.js")
		`))
	})

	Describe("unbundle:* imports", func() {
		It("should unbundle imports", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": {
					"/lib/foo3.js": "unbundle:/lib/foo3.js",
					"react-dom": "unbundle:react-dom"
				}
			}`))

			Expect(b.Build("lib/unbundle/local_modules.js")).To(ContainCode(`
				import "/lib/unbundle/foo1.js";
				import "/lib/unbundle/foo2.js";
				import "/lib/foo3.js";
				import { one } from "/packages/mypackage/treeshake.js";
				// packages/mypackage/index.js
	      console.log("node_modules/mypackage");
			`))
		})
	})

	Describe("vendored ruby gem", func() {
		It("resolves entry point", func() {
			types.Config.Engines = map[string]string{
				"gem3": filepath.Join(fixturesRoot, "dummy", "vendor", "gem3"),
			}

			result := b.Build("gem3/lib/gem3/gem3.js")

			Expect(result).To(ContainCode(`h1 { color: red; }`))
			Expect(result).To(ContainCode(`h2 { color: blue; }`))
			Expect(result).To(ContainCode(`function one(`))
			Expect(result).To(ContainCode(`console.log("gem3")`))
			Expect(result).To(ContainCode(`console.log("/lib/foo.js")`))
			Expect(result).To(ContainCode(`console.log("gem3/imported")`))
		})

		It("bundles", func() {
			types.Config.Engines = map[string]string{
				"gem3": filepath.Join(fixturesRoot, "dummy", "vendor", "gem3"),
			}

			result := b.Build("lib/gems/gem3.js")

			Expect(result).To(ContainCode(`h1 { color: red; }`))
			Expect(result).To(ContainCode(`h2 { color: blue; }`))
			Expect(result).To(ContainCode(`function one(`))
			Expect(result).To(ContainCode(`console.log("gem3")`))
			Expect(result).To(ContainCode(`console.log("/lib/foo.js")`))
			Expect(result).To(ContainCode(`console.log("gem3/imported")`))
		})
	})

	Describe("non-vendored ruby gem", func() {
		It("resolves entry point", func() {
			types.Config.Engines = map[string]string{
				"gem3": filepath.Join(fixturesRoot, "dummy", "vendor", "gem3"),
				"gem4": filepath.Join(fixturesRoot, "external", "gem4"),
			}

			result := b.Build("gem4/lib/gem4/gem4")

			Expect(result).To(ContainCode(`e.id = "_401b6cac";`))
			Expect(result).To(ContainCode(`.name-401b6cac`))
			Expect(result).To(ContainCode(`h1 { color: red; }`))
			Expect(result).To(ContainCode(`h2 { color: blue; }`))
			Expect(result).To(ContainCode(`function one(`))
			Expect(result).To(ContainCode(`console.log("gem4")`))
			Expect(result).To(ContainCode(`console.log("/lib/foo.js")`))
			Expect(result).To(ContainCode(`console.log("gem4/imported")`))
		})

		It("bundles", func() {
			types.Config.Engines = map[string]string{
				"gem3": filepath.Join(fixturesRoot, "dummy", "vendor", "gem3"),
				"gem4": filepath.Join(fixturesRoot, "external", "gem4"),
			}

			result := b.Build("lib/gems/gem4.js")

			Expect(result).To(ContainCode(`e.id = "_401b6cac";`))
			Expect(result).To(ContainCode(`.name-401b6cac`))
			Expect(result).To(ContainCode(`h1 { color: red; }`))
			Expect(result).To(ContainCode(`h2 { color: blue; }`))
			Expect(result).To(ContainCode(`function one(`))
			Expect(result).To(ContainCode(`console.log("gem4")`))
			Expect(result).To(ContainCode(`console.log("/lib/foo.js")`))
			Expect(result).To(ContainCode(`console.log("gem4/imported")`))
		})
	})

	It("tree shakes bare import", func() {
		Expect(b.Build("lib/import_tree_shake.js")).To(EqualCode(`
			// packages/mypackage/treeshake.js
			function one() {
				console.log("one");
			}

			// lib/import_tree_shake.js
			one();
		`))
	})

	It("does not bundle URLs", func() {
		MockURL("/import-url-module.js", "export default 'Hello World'")

		Expect(b.Build("lib/import_url.js")).To(ContainCode(`
			import myFunction from "https://proscenium.test/import-url-module.js";
		`))
	})

	It("should define NODE_ENV", func() {
		result := b.Build("lib/define_node_env.js")

		Expect(result).To(ContainCode(`console.log("test")`))
	})

	When("css", func() {
		It("should bundle absolute path", func() {
			Expect(b.Build("lib/import_absolute.css")).To(ContainCode(`
				.stuff {
					color: red;
				}
			`))
		})

		It("should bundle relative path", func() {
			result := b.Build("lib/import_relative.css")

			Expect(result).To(ContainCode(`
				.body {
					color: red;
				}
			`))
			Expect(result).To(ContainCode(`
				.body {
					color: blue;
				}
			`))
		})

		It("should not bundle fonts", func() {
			result := b.Build("lib/fonts.css")

			Expect(result).To(ContainCode(`url(/somefont.woff2)`))
			Expect(result).To(ContainCode(`url(/somefont.woff)`))
		})
	})
})

func BenchmarkBuild(bm *testing.B) {
	bm.ResetTimer()

	for i := 0; i < bm.N; i++ {
		result := b.Build("lib/foo.js")

		if len(result.Errors) > 0 {
			panic("Build failed: " + result.Errors[0].Text)
		}
	}
}
