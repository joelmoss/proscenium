package builder_test

import (
	"joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/internal/test"
	"os"
	"path"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/url", func() {
	BeforeEach(func() {
		builder.DiskvCache.EraseAll()
	})

	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	build := func(path string, rest ...interface{}) api.BuildResult {
		importMap := ""
		if len(rest) > 0 {
			importMap = rest[0].(string)
		}

		return builder.Build(builder.BuildOptions{
			Path:      path,
			Root:      root,
			ImportMap: []byte(importMap),
			Env:       2,
		})
	}

	When("direct build", func() {
		It("should bundle", func() {
			defer gock.Off()
			gock.New("https://proscenium.test").
				Get("/foo.js").
				Reply(200).
				BodyString("export default 'Hello World'")

			result := build("https%3A%2F%2Fproscenium.test%2Ffoo.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`= "Hello World";`))
		})
	})

	When("importing a URL", func() {
		It("should encode URL", func() {
			result := build("lib/import_url.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				import myFunction from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
			`))
		})
	})

	When("import map resolves to url", func() {
		It("should encode URL", func() {
			result := build("lib/import_map/bare_specifier.js", `{
				"imports": { "foo": "https://proscenium.test/import-url-module.js" }
			}`)

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				import foo from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
			`))
		})
	})

	When("importing an encoded URL", func() {
		It("should bundle decoded URL", func() {
			defer gock.Off()
			gock.New("https://proscenium.test").
				Get("/import-url-module.js").
				Reply(200).
				BodyString("export default () => { return 'Hello World' };")

			result := build("lib/import_encoded_url.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				return "Hello World"
			`))
		})

		It("should error on non-2** response", func() {
			defer gock.Off()
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

			defer gock.Off()
			gock.New("https://proscenium.test").
				Get("/import-url-module.js").
				Reply(200).
				BodyString("hello")

			result := build("lib/import_encoded_url.js")

			Expect(result.Errors[0].Text).To(Equal("Fetch of https://proscenium.test/import-url-module.js failed: http: request body too large"))
		})
	})

	When("importing encoded URL with relative dependency", func() {
		It("should resolve as URL ,encode and not bundle dependency", func() {
			defer gock.Off()
			gock.New("https://proscenium.test").
				Get("/import-url-module.js").
				Reply(200).
				BodyString(`
					import dep from './dependency';
					export default () => { return 'Hello World' + dep };
				`)

			result := build("lib/import_encoded_url.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`return "Hello World"`))
			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				import dep from "/https%3A%2F%2Fproscenium.test%2Fdependency";
			`))
		})
	})

	When("importing encoded URL with URL dependency", func() {
		It("should encode and not bundle dependency", func() {
			defer gock.Off()
			gock.New("https://proscenium.test").
				Get("/import-url-module.js").
				Reply(200).
				BodyString(`
					import dep from 'https://some.url/dependency';
					export default () => { return 'Hello World' + dep };
				`)

			result := build("lib/import_encoded_url.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`return "Hello World`))
			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				import dep from "/https%3A%2F%2Fsome.url%2Fdependency";
			`))
		})
	})

	When("importing encoded URL with bare dependency", func() {
		It("should pass through as is", func() {
			defer gock.Off()
			gock.New("https://proscenium.test").
				Get("/import-url-module.js").
				Reply(200).
				BodyString(`
					import dep from 'is-ip';
					export default () => { return 'Hello World' + dep };
				`)

			result := build("lib/import_encoded_url.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`return "Hello World`))
			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				import dep from "/node_modules/.pnpm/is-ip@
			`))
		})
	})
})
