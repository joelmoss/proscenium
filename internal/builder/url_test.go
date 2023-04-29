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

var _ = Describe("Internal/Builder.Build/url", func() {
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

	type buildOpts struct {
		ImportMap string
		Bundle    bool
	}

	build := func(path string, rest ...buildOpts) api.BuildResult {
		restOpts := buildOpts{}
		if len(rest) > 0 {
			restOpts = rest[0]
		}

		options := builder.BuildOptions{
			Path:   path,
			Root:   root,
			Bundle: restOpts.Bundle,
		}
		if restOpts.ImportMap != "" {
			options.ImportMap = []byte(restOpts.ImportMap)
		}

		return builder.Build(options)
	}

	When("entry point is encoded URL", func() {
		It("should bundle", func() {
			MockURL("/foo.js", "export default 'Hello World'")

			Expect(build("https%3A%2F%2Fproscenium.test%2Ffoo.js")).To(ContainCode(`= "Hello World";`))
		})

		When("bundling", func() {
			It("should bundle", func() {
				MockURL("/foo.js", "export default 'Hello World'")

				result := build("https%3A%2F%2Fproscenium.test%2Ffoo.js", buildOpts{Bundle: true})
				Expect(result).To(ContainCode(`= "Hello World";`))
			})
		})
	})

	When("importing a URL", func() {
		It("should encode URL", func() {
			Expect(build("lib/import_url.js")).To(ContainCode(`
				import myFunction from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
			`))
		})
	})

	When("import map resolves to url", func() {
		It("should encode URL", func() {
			result := build("lib/import_map/bare_specifier.js", buildOpts{ImportMap: `{
				"imports": { "foo": "https://proscenium.test/import-url-module.js" }
			}`})

			Expect(result).To(ContainCode(`
				import foo from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
			`))
		})
	})

	When("importing an encoded URL", func() {
		It("should bundle decoded URL", func() {
			MockURL("/import-url-module.js", "export default () => { return 'Hello World' };")

			Expect(build("lib/import_encoded_url.js")).To(ContainCode(`return "Hello World"`))
		})

		It("should error on non-2** response", func() {
			gock.New("https://proscenium.test").
				Get("/import-url-module.js").
				Reply(404)

			result := build("lib/import_encoded_url.js")

			Expect(result.Errors[0].Text).To(Equal("Fetch of https://proscenium.test/import-url-module.js failed with status code: 404"))
		})

		It("should error on reaching max response size", func() {
			originalMaxHttpBodySize := builder.MaxHttpBodySize
			builder.MaxHttpBodySize = 2
			defer func() { builder.MaxHttpBodySize = originalMaxHttpBodySize }()

			MockURL("/import-url-module.js", "hello")

			result := build("lib/import_encoded_url.js")

			Expect(result.Errors[0].Text).To(Equal("Fetch of https://proscenium.test/import-url-module.js failed: http: request body too large"))
		})
	})

	When("importing encoded URL with relative dependency", func() {
		It("should resolve as URL ,encode and not bundle dependency", func() {
			MockURL("/import-url-module.js", `
				import dep from './dependency';
				export default () => { return 'Hello World' + dep };
			`)

			result := build("lib/import_encoded_url.js")

			Expect(result).To(ContainCode(`return "Hello World"`))
			Expect(result).To(ContainCode(`
				import dep from "/https%3A%2F%2Fproscenium.test%2Fdependency";
			`))
		})
	})

	When("importing encoded URL with URL dependency", func() {
		It("should encode and not bundle dependency", func() {
			MockURL("/import-url-module.js", `
				import dep from 'https://some.url/dependency';
				export default () => { return 'Hello World' + dep };
			`)

			result := build("lib/import_encoded_url.js")

			Expect(result).To(ContainCode(`return "Hello World`))
			Expect(result).To(ContainCode(`
				import dep from "/https%3A%2F%2Fsome.url%2Fdependency";
			`))
		})
	})

	When("importing encoded URL with bare dependency", func() {
		It("should pass through as is", func() {
			MockURL("/import-url-module.js", `
				import dep from 'is-ip';
				export default () => { return 'Hello World' + dep };
			`)

			result := build("lib/import_encoded_url.js")

			Expect(result).To(ContainCode(`return "Hello World`))
			Expect(result).To(ContainCode(`
				import dep from "/node_modules/.pnpm/is-ip@
			`))
		})
	})
})
