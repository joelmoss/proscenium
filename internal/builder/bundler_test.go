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

var _ = Describe("Internal/Builder.bundler", func() {
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
			Path:   path,
			Root:   root,
			Bundle: true,
		})
	}

	It("tree shakes bare import", func() {
		Expect(build("lib/import_tree_shake.js")).To(EqualCode(`
			var __defProp = Object.defineProperty;
			var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

			// packages/mypackage/treeshake.js
			function one() {
				console.log("one");
			}
			__name(one, "one");

			// node_modules/.pnpm/lodash-es@4.17.21/node_modules/lodash-es/noop.js
			function noop() {
			}
			__name(noop, "noop");
			var noop_default = noop;

			// lib/import_tree_shake.js
			noop_default();
			one();
		`))
	})

	It("does not bundle URLs", func() {
		MockURL("/import-url-module.js", "export default 'Hello World'")

		Expect(build("lib/import_url.js")).To(ContainCode(`
			import myFunction from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
		`))
	})

	It("should define NODE_ENV", func() {
		result := build("lib/define_node_env.js")

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`console.log("test")`))
	})

	When("css", func() {
		It("should bundle absolute path", func() {
			Expect(build("lib/import_absolute.css")).To(ContainCode(`
				.stuff {
					color: red;
				}
			`))
		})

		It("should bundle relative path", func() {
			result := build("lib/import_relative.css")

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
			result := build("lib/fonts.css")

			Expect(result).To(ContainCode(`url(/somefont.woff2)`))
			Expect(result).To(ContainCode(`url(/somefont.woff)`))
		})
	})
})
