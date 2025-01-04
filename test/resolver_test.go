package proscenium_test

import (
	"joelmoss/proscenium/internal/importmap"
	r "joelmoss/proscenium/internal/resolver"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Resolve", func() {
	It("resolves unknown path", func() {
		path, err := r.Resolve("unknown", "")
		Expect(err).NotTo(Succeed())
		Expect(path).To(Equal(""))
	})

	It("resolves absolute path", func() {
		Expect(r.Resolve("/lib/foo.js", "")).To(Equal("/lib/foo.js"))
	})

	When("relative path without importer", func() {
		It("returns errors", func() {
			_, err := r.Resolve("./lib/foo.js", "")
			Expect(err).NotTo(Succeed())
		})
	})

	When("importer is given", func() {
		It("resolves relative path", func() {
			Expect(r.Resolve("./foo2.js", "/lib/foo.js")).To(Equal("/lib/foo2.js"))
		})
	})

	It("resolves bare specifier", func() {
		Expect(r.Resolve("mypackage", "")).To(Equal("/packages/mypackage/index.js"))
	})

	It("resolves directory to its index file", func() {
		result, _ := r.Resolve("/lib/indexes", "")

		Expect(result).To(Equal("/lib/indexes/index.js"))
	})

	It("resolves file without extension", func() {
		result, _ := r.Resolve("/lib/foo2", "")

		Expect(result).To(Equal("/lib/foo2.js"))
	})

	Describe("with import map", func() {
		It("resolves from import map", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": {
					"foo": "/lib/foo.js",
					"bar": "https://some.com/bar.js"
				}
			}`))

			Expect(r.Resolve("foo", "")).To(Equal("/lib/foo.js"))
			Expect(r.Resolve("bar", "")).To(Equal("https://some.com/bar.js"))
		})

		It("resolves directory to its index file", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "foo": "/lib/indexes" }
			}`))

			Expect(r.Resolve("foo", "")).To(Equal("/lib/indexes/index.js"))
		})

		It("resolves file without extension", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": { "foo": "/lib/foo2" }
			}`))

			Expect(r.Resolve("foo", "")).To(Equal("/lib/foo2.js"))
		})
	})
})

func BenchmarkResolve(b *testing.B) {
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		_, err := r.Resolve("/lib/foo2", "")
		if err != nil {
			panic("Build failed: " + err.Error())
		}
	}
}
