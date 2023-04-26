package resolver_test

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Resolver.Resolve", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
	})

	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	resolve := func(path string, importMap ...string) (string, error) {
		options := resolver.Options{
			Path: path,
			Root: root,
		}

		if len(importMap) > 0 {
			options.ImportMap = []byte(importMap[0])
		}

		return resolver.Resolve(options)
	}

	It("resolves unknown path", func() {
		path, err := resolve("unknown")
		Expect(err).NotTo(Succeed())
		Expect(path).To(Equal(""))
	})

	It("resolves absolute path", func() {
		Expect(resolve("/lib/foo.js")).To(Equal("/lib/foo.js"))
	})

	When("relative path without importer", func() {
		It("returns errors", func() {
			_, err := resolve("./lib/foo.js")
			Expect(err).NotTo(Succeed())
		})
	})

	When("importer is given", func() {
		resolve := func(path string, importer string) (string, error) {
			return resolver.Resolve(resolver.Options{
				Path:     path,
				Importer: importer,
				Root:     root,
			})
		}

		It("resolves relative path", func() {
			Expect(resolve("./foo2.js", "/lib/foo.js")).To(Equal("/lib/foo2.js"))
		})
	})

	It("resolves bare specifier", func() {
		Expect(resolve("mypackage")).To(Equal("/packages/mypackage/index.js"))
		Expect(resolve("is-ip")).To(Equal("/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js"))
	})

	It("resolves from import map", func() {
		im := `{
			"imports": {
				"foo": "/lib/foo.js",
				"bar": "https://some.com/bar.js"
			}
		}`

		Expect(resolve("foo", im)).To(Equal("/lib/foo.js"))
		Expect(resolve("bar", im)).To(Equal("/https%3A%2F%2Fsome.com%2Fbar.js"))
	})
})
