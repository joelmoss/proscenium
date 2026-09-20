package proscenium_test

import (
	r "joelmoss/proscenium/internal/resolver"
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Resolve", func() {
	It("resolves unknown path", func() {
		relPath, absPath, err := r.Resolve("unknown", "", testConfig)

		Expect(err).NotTo(Succeed())
		Expect(relPath).To(Equal(""))
		Expect(absPath).To(Equal(""))
	})

	It("resolves absolute path", func() {
		relPath, absPath, _ := r.Resolve("/lib/foo.js", "", testConfig)

		Expect(relPath).To(Equal("/lib/foo.js"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/lib/foo.js")))
	})

	// A URL has no file on disk. The file half used to be `path.Join(cfg.RootPath, url)`: a path
	// under the app root that could not exist.
	It("resolves a URL to itself, with no file", func() {
		relPath, absPath, err := r.Resolve("https://cdn.example/x.js", "", testConfig)

		Expect(err).NotTo(HaveOccurred())
		Expect(relPath).To(Equal("https://cdn.example/x.js"))
		Expect(absPath).To(Equal(""))
	})

	When("relative path without importer", func() {
		It("returns errors", func() {
			_, _, err := r.Resolve("./lib/foo.js", "", testConfig)
			Expect(err).NotTo(Succeed())
		})
	})

	When("importer is given", func() {
		// The importer is the absolute path of the file doing the importing, which is what
		// internal/css/mixins.go passes. A URL-path importer only ever worked by accident: the
		// app-root fallback was a TrimPrefix that did nothing, and the reparse at the end of
		// Resolve joined the root back on.
		It("resolves relative path", func() {
			importer := filepath.Join(testConfig.RootPath, "lib/foo.js")
			relPath, absPath, _ := r.Resolve("./foo2.js", importer, testConfig)

			Expect(relPath).To(Equal("/lib/foo2.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/lib/foo2.js")))
		})

		// Under neither the app root nor a gem, the joined path used to go out unchanged as the
		// URL path: an absolute filesystem path in a URL.
		It("refuses a path outside the app root and every gem", func() {
			importer := filepath.Join(fixturesRoot, "external/one/index.css")
			relPath, absPath, err := r.Resolve("./foo.css", importer, testConfig)

			Expect(err).To(MatchError(`"./foo.css" from "index.css" is outside the app root and every bundled gem`))
			Expect(relPath).To(Equal(""))
			Expect(absPath).To(Equal(""))
		})

		It("refuses a URL-path importer", func() {
			_, _, err := r.Resolve("./foo2.js", "/lib/foo.js", testConfig)

			Expect(err).To(MatchError(ContainSubstring("outside the app root and every bundled gem")))
		})
	})

	It("resolves bare specifier", func() {
		relPath, absPath, _ := r.Resolve("pkg", "", testConfig)

		Expect(relPath).To(Equal("/node_modules/pkg/index.js"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pkg/index.js")))
	})

	It("resolves file:* pnpm install", func() {
		relPath, absPath, _ := r.Resolve("pnpm-file/one.css", "", testConfig)

		Expect(relPath).To(Equal("/node_modules/pnpm-file/one.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pnpm-file/one.css")))
	})

	It("resolves external file:* pnpm install", func() {
		relPath, absPath, _ := r.Resolve("pnpm-file-ext/one.css", "", testConfig)

		Expect(relPath).To(Equal("/node_modules/pnpm-file-ext/one.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pnpm-file-ext/one.css")))
	})

	It("resolves link:* pnpm install", func() {
		relPath, absPath, _ := r.Resolve("pnpm-link/one.css", "", testConfig)

		Expect(relPath).To(Equal("/node_modules/pnpm-link/one.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pnpm-link/one.css")))
	})

	It("resolves external link:* pnpm install", func() {
		relPath, absPath, _ := r.Resolve("pnpm-link-ext/one.css", "", testConfig)

		Expect(relPath).To(Equal("/node_modules/pnpm-link-ext/one.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/node_modules/pnpm-link-ext/one.css")))
	})

	It("resolves @rubygems/* file:* pnpm install", func() {
		addGem("gem_file", "dummy/vendor")

		relPath, absPath, _ := r.Resolve("@rubygems/gem_file/index.module.css", "", testConfig)

		Expect(relPath).To(Equal("/node_modules/@rubygems/gem_file/index.module.css"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/vendor/gem_file/index.module.css")))
	})

	Context("relative @rubygems/*", func() {
		It("resolves gem", func() {
			addGem("gem1", "dummy/vendor")

			relPath, absPath, _ := r.Resolve("@rubygems/gem1/index.js", "", testConfig)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem1/index.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/vendor/gem1/index.js")))
		})

		It("resolves gem without file extension", func() {
			addGem("gem1", "dummy/vendor")

			relPath, absPath, _ := r.Resolve("@rubygems/gem1", "", testConfig)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem1/index.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/vendor/gem1/index.js")))
		})

		It("resolves relative path with importer", func() {
			addGem("gem3", "dummy/vendor")

			importer := filepath.Join(testConfig.RootPath, "/vendor/gem3/lib/gem3/styles.module.css")
			relPath, absPath, _ := r.Resolve("./red.css", importer, testConfig)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem3/lib/gem3/red.css"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/vendor/gem3/lib/gem3/red.css")))
		})
	})

	Context("external @rubygems/*", func() {
		It("resolves gem", func() {
			addGem("gem2", "external")

			relPath, absPath, _ := r.Resolve("@rubygems/gem2/lib/gem2/gem2.js", "", testConfig)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem2/lib/gem2/gem2.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem2/lib/gem2/gem2.js")))
		})

		It("resolves gem without file extension", func() {
			addGem("gem2", "external")

			relPath, absPath, _ := r.Resolve("@rubygems/gem2/lib/gem2/gem2", "", testConfig)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem2/lib/gem2/gem2.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem2/lib/gem2/gem2.js")))
		})

		It("resolves relative path with importer", func() {
			addGem("gem4", "external")

			importer := filepath.Join(testConfig.RootPath, "../external/gem4/lib/gem4/styles.module.css")
			relPath, absPath, _ := r.Resolve("./red.css", importer, testConfig)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem4/lib/gem4/red.css"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem4/lib/gem4/red.css")))
		})
	})

	Context("@rubygems/* specifier forms", func() {
		BeforeEach(func() {
			addGem("gem2", "external")
		})

		// The form a browser, or a `Proscenium::Importer.import` call, uses. It never reached the
		// gem branch; the reparse of the URL string at the end of Resolve was what turned it back
		// into the gem's file. Pinned before that reparse was deleted, because for a CSS module the
		// file path is what lib/proscenium/importer.rb hashes into the class names.
		It("resolves the served URL path of a gem file", func() {
			relPath, absPath, _ := r.Resolve("/node_modules/@rubygems/gem2/lib/gem2/gem2.js", "", testConfig)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem2/lib/gem2/gem2.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem2/lib/gem2/gem2.js")))
		})

		It("reports an unknown gem in the served URL path form", func() {
			_, _, err := r.Resolve("/node_modules/@rubygems/nope/x.js", "", testConfig)

			Expect(err).To(MatchError(`could not resolve Ruby gem "nope". Is "nope" in your Gemfile?`))
		})

		It("reports an unknown gem", func() {
			_, _, err := r.Resolve("@rubygems/nope/x.js", "", testConfig)

			Expect(err).To(MatchError(`could not resolve Ruby gem "nope". Is "nope" in your Gemfile?`))
		})

		// `IsRubyGem` accepted this form, and `ResolveRubyGem` then read the scope as the gem name.
		It("resolves the node_modules-prefixed form", func() {
			relPath, absPath, _ := r.Resolve("node_modules/@rubygems/gem2/lib/gem2/gem2.js", "", testConfig)

			Expect(relPath).To(Equal("/node_modules/@rubygems/gem2/lib/gem2/gem2.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem2/lib/gem2/gem2.js")))
		})

		// The gem has both `dir.js` and `dir/index.js`. esbuild reads the trailing slash as "the
		// directory", and cleaning the suffix used to drop it, silently picking the file.
		It("keeps a trailing slash, which picks the directory over the file of the same name", func() {
			addGem("gem4", "external")

			relPath, absPath, _ := r.Resolve("@rubygems/gem4/dir/", "", testConfig)
			Expect(relPath).To(Equal("/node_modules/@rubygems/gem4/dir/index.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem4/dir/index.js")))

			relPath, absPath, _ = r.Resolve("@rubygems/gem4/dir", "", testConfig)
			Expect(relPath).To(Equal("/node_modules/@rubygems/gem4/dir.js"))
			Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/external/gem4/dir.js")))
		})

		// Used to answer with a URL naming gem4 and a file path under gem2's parent directory.
		It("refuses a suffix that escapes the gem root", func() {
			addGem("gem4", "external")

			_, _, err := r.Resolve("@rubygems/gem2/../gem4/lib/gem4/gem4.js", "", testConfig)

			Expect(err).To(MatchError(`"@rubygems/gem2/../gem4/lib/gem4/gem4.js" escapes the root of gem "gem2"`))
		})
	})

	It("resolves directory to its index file", func() {
		relPath, absPath, _ := r.Resolve("/lib/indexes", "", testConfig)

		Expect(relPath).To(Equal("/lib/indexes/index.js"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/lib/indexes/index.js")))
	})

	It("resolves file without extension", func() {
		relPath, absPath, _ := r.Resolve("/lib/foo2", "", testConfig)

		Expect(relPath).To(Equal("/lib/foo2.js"))
		Expect(absPath).To(Equal(filepath.Join(fixturesRoot, "/dummy/lib/foo2.js")))
	})
})

func BenchmarkResolve(b *testing.B) {
	cfg := newTestConfig()

	for b.Loop() {
		_, _, err := r.Resolve("/lib/foo2", "", cfg)
		if err != nil {
			panic("Build failed: " + err.Error())
		}
	}
}
