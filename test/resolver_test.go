package proscenium_test

import (
	. "joelmoss/proscenium/test/support"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Resolve", func() {
	It("resolves unknown path", func() {
		path, err := Resolve("unknown")
		Expect(err).NotTo(Succeed())
		Expect(path).To(Equal(""))
	})

	It("resolves absolute path", func() {
		Expect(Resolve("/lib/foo.js")).To(Equal("/lib/foo.js"))
	})

	When("relative path without importer", func() {
		It("returns errors", func() {
			_, err := Resolve("./lib/foo.js")
			Expect(err).NotTo(Succeed())
		})
	})

	When("importer is given", func() {
		It("resolves relative path", func() {
			Expect(Resolve("./foo2.js", ResolveOpts{Importer: "/lib/foo.js"})).To(Equal("/lib/foo2.js"))
		})
	})

	It("resolves bare specifier", func() {
		Expect(Resolve("mypackage")).To(Equal("/packages/mypackage/index.js"))
		Expect(Resolve("is-ip")).To(Equal("/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js"))
	})

	It("resolves directory to its index file", func() {
		result, _ := Resolve("/lib/indexes")

		Expect(result).To(Equal("/lib/indexes/index.js"))
	})

	It("resolves file without extension", func() {
		result, _ := Resolve("/lib/foo2")

		Expect(result).To(Equal("/lib/foo2.js"))
	})

	Describe("with import map", func() {
		It("resolves from import map", func() {
			im := `{
				"imports": {
					"foo": "/lib/foo.js",
					"bar": "https://some.com/bar.js"
				}
			}`

			Expect(Resolve("foo", ResolveOpts{ImportMap: im})).To(Equal("/lib/foo.js"))
			Expect(Resolve("bar", ResolveOpts{ImportMap: im})).To(Equal("/https%3A%2F%2Fsome.com%2Fbar.js"))
		})

		It("produces error on invalid json", func() {
			_, err := Resolve("lib/foo.js", ResolveOpts{ImportMap: `{[}]}`})

			Expect(err.Error()).To(Equal(
				"Failed to parse import map: *json.SyntaxError: invalid character '[' looking for beginning of object key string",
			))
		})

		It("resolves directory to its index file", func() {
			result, _ := Resolve("foo", ResolveOpts{
				ImportMap: `{
						"imports": { "foo": "/lib/indexes" }
					}`,
			})

			Expect(result).To(Equal("/lib/indexes/index.js"))
		})

		It("resolves file without extension", func() {
			result, _ := Resolve("foo", ResolveOpts{
				ImportMap: `{
						"imports": { "foo": "/lib/foo2" }
					}`,
			})

			Expect(result).To(Equal("/lib/foo2.js"))
		})
	})
})

func BenchmarkResolve(b *testing.B) {
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		_, err := Resolve("/lib/foo2")
		if err != nil {
			panic("Build failed: " + err.Error())
		}
	}
}
