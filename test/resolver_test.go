package proscenium_test

import (
	r "joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Resolve", func() {
	It("resolves unknown path", func() {
		relPath, absPath, err := r.Resolve("unknown", "")

		Expect(err).NotTo(Succeed())
		Expect(relPath).To(Equal(""))
		Expect(absPath).To(Equal(""))
	})

	It("resolves absolute path", func() {
		relPath, absPath, _ := r.Resolve("/lib/foo.js", "")

		Expect(relPath).To(Equal("/lib/foo.js"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/lib/foo.js")))
	})

	When("relative path without importer", func() {
		It("returns errors", func() {
			_, _, err := r.Resolve("./lib/foo.js", "")
			Expect(err).NotTo(Succeed())
		})
	})

	When("importer is given", func() {
		It("resolves relative path", func() {
			relPath, absPath, _ := r.Resolve("./foo2.js", "/lib/foo.js")

			Expect(relPath).To(Equal("/lib/foo2.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/lib/foo2.js")))
		})
	})

	It("resolves bare specifier", func() {
		relPath, absPath, _ := r.Resolve("pkg", "")

		Expect(relPath).To(Equal("/node_modules/pkg/index.js"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pkg/index.js")))
	})

	It("resolves file:* pnpm install", func() {
		relPath, absPath, _ := r.Resolve("pnpm-file/one.css", "")

		Expect(relPath).To(Equal("/node_modules/pnpm-file/one.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pnpm-file/one.css")))
	})

	It("resolves external file:* pnpm install", func() {
		relPath, absPath, _ := r.Resolve("pnpm-file-ext/one.css", "")

		Expect(relPath).To(Equal("/node_modules/pnpm-file-ext/one.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pnpm-file-ext/one.css")))
	})

	It("resolves link:* pnpm install", func() {
		relPath, absPath, _ := r.Resolve("pnpm-link/one.css", "")

		Expect(relPath).To(Equal("/node_modules/pnpm-link/one.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pnpm-link/one.css")))
	})

	It("resolves external link:* pnpm install", func() {
		relPath, absPath, _ := r.Resolve("pnpm-link-ext/one.css", "")

		Expect(relPath).To(Equal("/node_modules/pnpm-link-ext/one.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pnpm-link-ext/one.css")))
	})

	It("resolves @rubygems/* file:* pnpm install", func() {
		addGem("gem_file", "dummy/vendor")

		relPath, absPath, _ := r.Resolve("@rubygems/gem_file/index.module.css", "")

		Expect(relPath).To(Equal("/node_modules/@rubygems/gem_file/index.module.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/vendor/gem_file/index.module.css")))
	})

	Context("relative @rubygems/*", func() {
		It("resolves gem", func() {
			addGem("gem1", "dummy/vendor")

			relPath, absPath, _ := r.Resolve("@rubygems/gem1/index.js", "")

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem1/index.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/vendor/gem1/index.js")))
		})

		It("resolves gem without file extension", func() {
			addGem("gem1", "dummy/vendor")

			relPath, absPath, _ := r.Resolve("@rubygems/gem1", "")

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem1/index.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/vendor/gem1/index.js")))
		})

		It("resolves relative path with importer", func() {
			addGem("gem3", "dummy/vendor")

			importer := filepath.Join(types.Config.RootPath, "/vendor/gem3/lib/gem3/styles.module.css")
			relPath, absPath, _ := r.Resolve("./red.css", importer)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem3/lib/gem3/red.css"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/vendor/gem3/lib/gem3/red.css")))
		})
	})

	Context("external @rubygems/*", func() {
		It("resolves gem", func() {
			addGem("gem2", "external")

			relPath, absPath, _ := r.Resolve("@rubygems/gem2/lib/gem2/gem2.js", "")

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem2/lib/gem2/gem2.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem2/lib/gem2/gem2.js")))
		})

		It("resolves gem without file extension", func() {
			addGem("gem2", "external")

			relPath, absPath, _ := r.Resolve("@rubygems/gem2/lib/gem2/gem2", "")

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem2/lib/gem2/gem2.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem2/lib/gem2/gem2.js")))
		})

		It("resolves relative path with importer", func() {
			addGem("gem4", "external")

			importer := filepath.Join(types.Config.RootPath, "../external/gem4/lib/gem4/styles.module.css")
			relPath, absPath, _ := r.Resolve("./red.css", importer)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem4/lib/gem4/red.css"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem4/lib/gem4/red.css")))
		})
	})

	It("resolves directory to its index file", func() {
		relPath, absPath, _ := r.Resolve("/lib/indexes", "")

		Expect(relPath).To(Equal("/lib/indexes/index.js"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/lib/indexes/index.js")))
	})

	It("resolves file without extension", func() {
		relPath, absPath, _ := r.Resolve("/lib/foo2", "")

		Expect(relPath).To(Equal("/lib/foo2.js"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/lib/foo2.js")))
	})
})

func BenchmarkResolve(b *testing.B) {
	for b.Loop() {
		_, _, err := r.Resolve("/lib/foo2", "")
		if err != nil {
			panic("Build failed: " + err.Error())
		}
	}
}
