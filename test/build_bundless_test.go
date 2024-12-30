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

var _ = Describe("Build bundless", func() {
	BeforeEach(func() {
		types.Config.Bundle = false
	})

	It("should fail on unknown entrypoint", func() {
		result := b.Build("unknown.js")

		Expect(result.Errors[0].Text).To(Equal("Could not resolve \"unknown.js\""))
	})

	It("should build entrypoint", func() {
		Expect(b.Build("lib/foo.js")).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("should not build entrypoint with import map", func() {
		importmap.NewJsonImportMap([]byte(`{
			"imports": {
				"/lib/foo.js": "/lib/foo2.js"
			}
		}`))
		Expect(b.Build("lib/foo.js")).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("should leave rjs imports untouched", func() {
		Expect(b.Build("lib/rjs.js")).To(ContainCode(`import foo from "/constants.rjs"`))
	})

	It("should resolve bare module", func() {
		Expect(b.Build("lib/import_npm_module.js")).To(ContainCode(`
			import { one } from "/packages/mypackage/treeshake.js";
      one();
		`))
	})

	It("should resolve extension-less imports", func() {
		Expect(b.Build("lib/import_absolute_module_without_extension.js")).To(ContainCode(`
			import foo from "/lib/foo2.js";
		`))
	})

	It("should resolve relative path", func() {
		Expect(b.Build("lib/import_relative_module.js")).To(ContainCode(`
			import foo4 from "/lib/foo4.js";
			foo4();
		`))
	})

	It("should resolve absolute path", func() {
		Expect(b.Build("lib/import_absolute_module.js")).To(ContainCode(`
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

		Expect(b.Build("lib/import_absolute_module.js")).To(ContainCode(`
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

		Expect(b.Build("lib/unbundle/local_modules.js")).To(ContainCode(`
				import "/lib/unbundle/foo1.js";
				import "/lib/unbundle/foo2.js";
				import "/lib/foo32.js";
				import { one } from "/packages/mypackage/treeshake.js";
				import "/packages/mypackage/index.js";
			`))
	})

	Describe("vendored ruby gem", func() {
		var _ = BeforeEach(func() {
			types.Config.Engines = map[string]string{
				"gem3": filepath.Join(fixturesRoot, "dummy", "vendor", "gem3"),
			}
		})

		It("should fail on unknown entrypoint", func() {
			result := b.Build("unknown.js")

			Expect(result.Errors[0].Text).To(Equal("Could not resolve \"unknown.js\""))
		})

		It("engine is resolved before import map", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": {
					"/gem3/lib/gem3/console.js": "/lib/foo.js",
				}
			}`))

			result := b.Build("lib/engines/gem3.js")

			Expect(result).To(ContainCode(`import "/vendor/gem3/lib/gem3/console.js";`))
		})

		It("should resolve extension-less imports", func() {
			result := b.Build("gem3/lib/gem3/gem3.js")

			Expect(result).To(ContainCode(`import "/vendor/gem3/lib/gem3/foo.js";`))
		})

		It("should fail on engined but unknown entrypoint", func() {
			result := b.Build("gem3/unknown.js")

			Expect(result.Errors[0].Text).To(HavePrefix("Could not read from file: /"))
		})

		It("resolves entry point", func() {
			result := b.Build("gem3/lib/gem3/console.js")

			Expect(result).To(ContainCode(`console.log("gem3");`))
		})

		It("resolves absolute and same engine imports", func() {
			result := b.Build("gem3/lib/gem3/gem3.js")

			Expect(result).To(ContainCode(`
				import "/vendor/gem3/lib/gem3/console.js";
			`))
		})

		It("resolves bare import to Rails app (not engine)", func() {
			result := b.Build("gem3/lib/gem3/gem3.js")

			Expect(result).To(ContainCode(`
				import { one } from "/packages/mypackage/treeshake.js";
			`))
		})

		It("resolves relative import to engine", func() {
			result := b.Build("gem3/lib/gem3/gem3.js")

			Expect(result).To(ContainCode(`
				import imported from "/vendor/gem3/lib/gem3/imported.js";
			`))
		})

		It("resolves absolute import to Rails app (not engine)", func() {
			result := b.Build("gem3/lib/gem3/gem3.js")

			Expect(result).To(ContainCode(`
				import "/lib/foo.js";
			`))
		})

		It("resolves import from engine when in app", func() {
			result := b.Build("lib/gems/gem3.js")

			Expect(result).To(ContainCode(`import "/vendor/gem3/lib/gem3/gem3.js"`))
		})
	})

	Describe("non-vendored ruby gem", func() {
		var _ = BeforeEach(func() {
			types.Config.Engines = map[string]string{
				"gem4": filepath.Join(fixturesRoot, "external", "gem4"),
			}
		})

		It("should fail on unknown entrypoint", func() {
			result := b.Build("unknown.js")

			Expect(result.Errors[0].Text).To(Equal("Could not resolve \"unknown.js\""))
		})

		It("should fail on engined but unknown entrypoint", func() {
			result := b.Build("gem4/unknown.js")

			Expect(result.Errors[0].Text).To(HavePrefix("Could not read from file: /"))
		})

		It("resolves entry point", func() {
			result := b.Build("gem4/lib/gem4/console.js")

			Expect(result).To(ContainCode(`console.log("gem4");`))
		})

		It("resolves absolute and same engine imports", func() {
			result := b.Build("gem4/lib/gem4/gem4.js")

			Expect(result).To(ContainCode(`
				import "/gem4/lib/gem4/console.js";
			`))
		})

		It("resolves other engine imports", func() {
			result := b.Build("gem4/lib/gem4/gem4.js")

			Expect(result).To(ContainCode(`
				import "/gem3/lib/gem3/console.js";
			`))
		})

		It("resolves bare import to Rails app (not engine)", func() {
			result := b.Build("gem4/lib/gem4/gem4.js")

			Expect(result).To(ContainCode(`
				import { one } from "/packages/mypackage/treeshake.js";
			`))
		})

		It("resolves relative import to engine", func() {
			result := b.Build("gem4/lib/gem4/gem4.js")

			Expect(result).To(ContainCode(`
				import imported from "/gem4/lib/gem4/imported.js";
			`))
		})

		It("resolves absolute import to Rails app (not engine)", func() {
			result := b.Build("gem4/lib/gem4/gem4.js")

			Expect(result).To(ContainCode(`
				import "/lib/foo.js";
			`))
		})

		It("resolves import from engine when in app", func() {
			result := b.Build("lib/gems/gem4.js")

			Expect(result).To(ContainCode(`import "/gem4/lib/gem4/gem4.js"`))
		})
	})

	It("should define NODE_ENV", func() {
		result := b.Build("lib/define_node_env.js")

		Expect(result).To(ContainCode(`console.log("test")`))
	})
})
