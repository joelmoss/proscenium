package builder_test

import (
	"joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/internal/test"
	"os"
	"path"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/k0kubun/pp/v3"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder", func() {
	Describe("Build", func() {
		var cwd, _ = os.Getwd()
		var root string = path.Join(cwd, "../../", "test", "internal")

		build := func(path string) api.BuildResult {
			return builder.Build(builder.BuildOptions{
				Path: path,
				Root: root,
				Env:  2,
			})
		}

		It("should fail on unknown entrypoint", func() {
			result := build("unknown.js")

			Expect(result.Errors[0].Text).To(Equal("Could not resolve \"unknown.js\""))
		})

		It("should build js", func() {
			result := build("lib/foo.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`console.log("/lib/foo.js")`))
		})

		It("should build jsx", func() {
			result := build("lib/component.jsx")

			Expect(path.Join(path.Join(root, "public/assets"), "lib/component.js")).To(
				Equal(result.OutputFiles[0].Path))
		})

		It("should build css", func() {
			result := build("lib/foo.css")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			.body { color: red; }
		`))
		})

		It("should import bare module", func() {
			result := build("lib/import_npm_module.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			import { isIP } from "/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js"
		`))
		})

		It("should import relative path", func() {
			result := build("lib/import_relative_module.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			import foo4 from "/lib/foo4.js"
		`))
		})

		It("should import absolute path", func() {
			result := build("lib/import_absolute_module.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			import foo4 from "/lib/foo4.js"
		`))
		})

		It("import css module from js", Pending, func() {
			result := build("lib/import_css_module.js")

			pp.Println(result)
			pp.Println(string(result.OutputFiles[0].Contents))

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`import foo4 from "/lib/foo4.js"`))
		})

		It("should define NODE_ENV", func() {
			result := build("lib/define_node_env.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`console.log("test")`))
		})

		When("ImportMap is given", func() {
			build := func(path string, importMap string) api.BuildResult {
				return builder.Build(builder.BuildOptions{
					Path:      path,
					Root:      root,
					Env:       2,
					Debug:     true,
					ImportMap: []byte(importMap),
				})
			}

			It("should parse js import map", func() {
				result := builder.Build(builder.BuildOptions{
					Path:          "lib/import_map/as_js.js",
					Root:          root,
					Env:           2,
					Debug:         true,
					ImportMapPath: "config/import_maps/as.js",
				})

				Expect(result.OutputFiles[0].Contents).To(ContainCode(`import pkg from "/lib/foo2.js";`))
			})

			It("bare specifier", func() {
				result := build("lib/import_map/bare_specifier.js", `{
					"imports": { "foo": "/lib/foo.js" }
				}`)

				Expect(result.OutputFiles[0].Contents).To(ContainCode(`import foo from "/lib/foo.js";`))
			})

			It("path prefix", Pending, func() {
				// import four from 'one/two/three/four.js'
				result := build("lib/import_map/path_prefix.js", `{
					"imports": { "one/": "./src/one/" }
				}`)

				Expect(result.OutputFiles[0].Contents).To(ContainCode(`
					import four from "./src/one/two/three/four.js";
				`))
			})

			It("scopes", Pending, func() {
				result := build("lib/import_map/scopes.js", `{
					"imports": {
						"foo": "/lib/foo.js"
					},
					"scopes": {
						"/lib/import_map/": {
							"foo": "/lib/foo4.js"
						}
					}
				}`)

				Expect(result.OutputFiles[0].Contents).To(ContainCode(`import foo from "/lib/foo4.js";`))
			})

			It("path prefix multiple matches", Pending, func() {
				result := build("lib/import_map/path_prefix.js", `{
					"imports": {
						"one/": "./one/",
						"one/two/three/": "./three/",
						"one/two/": "./two/"
					}
				}`)

				Expect(result.OutputFiles[0].Contents).To(ContainCode(`
					import four from "./three/four.js";
				`))
			})
		})
	})
})
