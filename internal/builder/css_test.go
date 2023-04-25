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
			Path:          path,
			Root:          root,
			Env:           2,
			ImportMapPath: "config/import_maps/no_imports.json",
		})
	}

	It("should build css", func() {
		result := build("lib/foo.css")

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			.body { color: red; }
		`))
	})

	It("should build css module", func() {
		result := build("app/components/phlex/side_load_css_module_view.module.css")

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			.base03b26e31 { color: red; }
		`))
	})

	It("should import absolute path", func() {
		result := build("lib/import_absolute.css")

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			@import "/config/foo.css";
		`))
	})

	It("should import relative path", func() {
		result := build("lib/import_relative.css")

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			@import "/lib/foo.css";
			@import "/lib/foo2.css";
		`))
	})

	When("mixin from URL", func() {
		It("is replaced with defined mixin", func() {
			result := build("lib/with_mixin_from_url.css")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				a {
					color: red;
					font-size: 20px;
				}
			`))
		})
	})

	When("importing bare specifier", func() {
		It("is replaced with absolute path", func() {
			result := build("lib/import_npm_module.css")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				@import "/node_modules/.pnpm/normalize.css@8.0.1/node_modules/normalize.css/normalize.css";
			`))
		})
	})

	PIt("import css module from js", func() {
		result := build("lib/import_css_module.js")

		pp.Println(result)
		pp.Println(string(result.OutputFiles[0].Contents))

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`import foo4 from "/lib/foo4.js"`))
	})
})
