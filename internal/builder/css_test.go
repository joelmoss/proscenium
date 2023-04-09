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

var _ = Describe("Internal/Builder.Build/css", func() {
	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	build := func(path string) api.BuildResult {
		return builder.Build(builder.BuildOptions{
			Path: path,
			Root: root,
			Env:  2,
		})
	}

	It("should build css", func() {
		result := build("lib/foo.css")

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			.body { color: red; }
		`))
	})

	Describe("mixin from URL", func() {
		It("mixin is replaced with defined mixin", func() {
			result := build("lib/with_mixin_from_url.css")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				a {
					color: red;
					font-size: 20px;
				}
			`))
		})
	})

	It("import css module from js", Pending, func() {
		result := build("lib/import_css_module.js")

		pp.Println(result)
		pp.Println(string(result.OutputFiles[0].Contents))

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`import foo4 from "/lib/foo4.js"`))
	})
})
