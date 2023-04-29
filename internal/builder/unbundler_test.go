package builder_test

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	. "joelmoss/proscenium/internal/test"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.unbundler", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		builder.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	build := func(path string) api.BuildResult {
		return builder.Build(builder.BuildOptions{
			Path: path,
			Root: root,
		})
	}

	It("should fail on unknown entrypoint", func() {
		result := build("unknown.js")

		Expect(result.Errors[0].Text).To(Equal("Could not resolve \"unknown.js\""))
	})

	It("should build js", func() {
		Expect(build("lib/foo.js")).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("should build jsx", func() {
		result := build("lib/component.jsx")

		Expect(path.Join(path.Join(root, "public/assets"), "lib/component.js")).To(
			Equal(result.OutputFiles[0].Path))
	})

	It("should import bare module", func() {
		Expect(build("lib/import_npm_module.js")).To(ContainCode(`
			import { isIP } from "/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js"
		`))
	})

	It("should import relative path", func() {
		Expect(build("lib/import_relative_module.js")).To(ContainCode(`
			import foo4 from "/lib/foo4.js"
		`))
	})

	It("should import absolute path", func() {
		Expect(build("lib/import_absolute_module.js")).To(ContainCode(`
			import foo4 from "/lib/foo4.js"
		`))
	})

	It("should define NODE_ENV", func() {
		Expect(build("lib/define_node_env.js")).To(ContainCode(`console.log("test")`))
	})
})
