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

var _ = Describe("Internal/Builder.Build", func() {
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

	It("should define NODE_ENV", func() {
		result := build("lib/define_node_env.js")

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`console.log("test")`))
	})
})
