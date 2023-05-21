package builder_test

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	. "joelmoss/proscenium/internal/testing"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/import_map", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		plugin.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	It("produces error on invalid json", func() {
		result := Build("lib/foo.js", BuildOpts{ImportMap: `{[}]}`})

		Expect(result.Errors[0].Text).To(Equal("Failed to parse import map"))
	})

	When("import map is JS", func() {
		var cwd, _ = os.Getwd()
		var root string = path.Join(cwd, "../../", "test", "internal")

		It("should parse", func() {
			result := builder.Build(builder.BuildOptions{
				Path:          "lib/import_map/as_js.js",
				Root:          root,
				ImportMapPath: "config/import_maps/as.js",
			})

			Expect(result).To(ContainCode(`console.log("/lib/foo2.js");`))
		})

		It("produces error when invalid", func() {
			result := builder.Build(builder.BuildOptions{
				Path:          "lib/foo.js",
				Root:          root,
				ImportMapPath: "config/import_maps/invalid.js",
			})

			Expect(result.Errors[0].Text).To(Equal("Failed to parse import map"))
		})
	})

	When("specifier is bare", func() {
		When("value starts with /", func() {
			It("resolves", func() {
				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "/lib/foo.js" }
					}`,
				})

				Expect(result).To(ContainCode(`console.log("/lib/foo.js");`))
			})
		})

		When("value starts with ./ or ../", func() {
			It("resolves", func() {
				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "../foo.js" }
					}`,
				})

				Expect(result).To(ContainCode(`console.log("/lib/foo.js");`))
			})
		})

		When("value is URL", func() {
			It("is not bundled", func() {
				MockURL("/foo.js", "console.log('foo');")

				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "https://proscenium.test/foo.js" }
					}`,
				})

				Expect(result).To(ContainCode(`
					import foo from "/https%3A%2F%2Fproscenium.test%2Ffoo.js";
				`))
			})
		})

		When("value is bare specifier", func() {
			It("resolves the value", func() {
				result := Build("lib/import_map/bare_specifier.js", BuildOpts{
					ImportMap: `{
						"imports": { "foo": "mypackage" }
					}`,
				})

				Expect(result).To(ContainCode(`
					console.log("node_modules/mypackage");
				`))
			})
		})
	})

	// It("path prefix", Pending, func() {
	// 	// import four from 'one/two/three/four.js'
	// 	result := Build("lib/import_map/path_prefix.js", `{
	// 		"imports": { "one/": "./src/one/" }
	// 	}`)

	// 	Expect(result.OutputFiles[0].Contents).To(ContainCode(`
	// 		import four from "./src/one/two/three/four.js";
	// 	`))
	// })

	// It("scopes", Pending, func() {
	// 	result := Build("lib/import_map/scopes.js", `{
	// 		"imports": {
	// 			"foo": "/lib/foo.js"
	// 		},
	// 		"scopes": {
	// 			"/lib/import_map/": {
	// 				"foo": "/lib/foo4.js"
	// 			}
	// 		}
	// 	}`)

	// 	Expect(result.OutputFiles[0].Contents).To(ContainCode(`import foo from "/lib/foo4.js";`))
	// })

	// It("path prefix multiple matches", Pending, func() {
	// 	result := Build("lib/import_map/path_prefix.js", `{
	// 		"imports": {
	// 			"one/": "./one/",
	// 			"one/two/three/": "./three/",
	// 			"one/two/": "./two/"
	// 		}
	// 	}`)

	// 	Expect(result.OutputFiles[0].Contents).To(ContainCode(`
	// 		import four from "./three/four.js";
	// 	`))
	// })
})
