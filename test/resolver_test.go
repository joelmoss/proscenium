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
		Expect(r.Resolve("pkg", "")).To(Equal("/node_modules/pkg/index.js"))
	})

	It("resolves file:* pnpm install", func() {
		Expect(r.Resolve("pnpm-file/one.css", "")).To(
			Equal("/node_modules/pnpm-file/one.css"),
		)
	})

	It("resolves external file:* pnpm install", func() {
		Expect(r.Resolve("pnpm-file-ext/one.css", "")).To(
			Equal("/node_modules/pnpm-file-ext/one.css"),
		)
	})

	It("resolves link:* pnpm install", func() {
		Expect(r.Resolve("pnpm-link/one.css", "")).To(
			Equal("/node_modules/pnpm-link/one.css"),
		)
	})

	It("resolves external link:* pnpm install", func() {
		Expect(r.Resolve("pnpm-link-ext/one.css", "")).To(
			Equal("/node_modules/pnpm-link-ext/one.css"),
		)
	})

	It("resolves @rubygems/* file:* pnpm install", func() {
		addGem("gem_file", "dummy/vendor")

		Expect(r.Resolve("@rubygems/gem_file/index.module.css", "")).To(
			Equal("/node_modules/@rubygems/gem_file/index.module.css"),
		)
	})

	Context("relative @rubygems/*", func() {
		It("resolves gem", func() {
			addGem("gem1", "dummy/vendor")

			Expect(r.Resolve("@rubygems/gem1/index.js", "")).To(Equal(
				"/node_modules/@rubygems/gem1/index.js",
			))
		})

		It("resolves gem without file extension", func() {
			addGem("gem1", "dummy/vendor")

			Expect(r.Resolve("@rubygems/gem1", "")).To(Equal("/node_modules/@rubygems/gem1/index.js"))
		})

		It("resolves relative path with importer", func() {
			addGem("gem3", "dummy/vendor")

			importer := "/Users/joelmoss/dev/proscenium/fixtures/dummy/vendor/gem3/lib/gem3/styles.module.css"
			Expect(r.Resolve("./red.css", importer)).To(Equal(
				"/node_modules/@rubygems/gem3/lib/gem3/red.css",
			))
		})
	})

	Context("external @rubygems/*", func() {
		It("resolves gem", func() {
			addGem("gem2", "external")

			Expect(r.Resolve("@rubygems/gem2/lib/gem2/gem2.js", "")).To(Equal(
				"/node_modules/@rubygems/gem2/lib/gem2/gem2.js",
			))
		})

		It("resolves gem without file extension", func() {
			addGem("gem2", "external")

			Expect(r.Resolve("@rubygems/gem2/lib/gem2/gem2", "")).To(Equal(
				"/node_modules/@rubygems/gem2/lib/gem2/gem2.js",
			))
		})

		It("resolves relative path with importer", func() {
			addGem("gem4", "external")

			importer := "/Users/joelmoss/dev/proscenium/fixtures/external/gem4/lib/gem4/styles.module.css"
			Expect(r.Resolve("./red.css", importer)).To(Equal(
				"/node_modules/@rubygems/gem4/lib/gem4/red.css",
			))
		})
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
