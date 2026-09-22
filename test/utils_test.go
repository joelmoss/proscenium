package proscenium_test

import (
	"fmt"
	"runtime"
	"testing"

	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// internal/utils had no test file at all. The config here is built inline rather than from
// `testConfig`, whose gem set is whatever the dummy app's Gemfile happens to hold - these cases
// need roots that share string prefixes and nest inside one another, which no real Gemfile
// guarantees.
var _ = Describe("utils gem references", func() {
	var cfg *types.ConfigT

	BeforeEach(func() {
		cfg = &types.ConfigT{RubyGems: map[string]string{
			"foo":     "/gems/foo",
			"foo-ext": "/gems/foo-ext",
			"nested":  "/gems/foo/vendor/nested",
		}}
	})

	Describe("GemFromSpecifier", func() {
		DescribeTable("parses a bundled gem specifier",
			func(spec string, suffix string) {
				ref, isGem, err := utils.GemFromSpecifier(spec, cfg)

				Expect(err).NotTo(HaveOccurred())
				Expect(isGem).To(BeTrue())
				Expect(ref.Name).To(Equal("foo"))
				Expect(ref.Root).To(Equal("/gems/foo"))
				Expect(ref.Suffix).To(Equal(suffix))
			},
			Entry("bare", "@rubygems/foo", ""),
			Entry("trailing slash", "@rubygems/foo/", ""),
			Entry("with a suffix", "@rubygems/foo/bar.js", "/bar.js"),
			Entry("nested suffix", "@rubygems/foo/lib/bar.js", "/lib/bar.js"),
			Entry("node_modules prefixed", "node_modules/@rubygems/foo/bar.js", "/bar.js"),
			Entry("rooted node_modules prefixed", "/node_modules/@rubygems/foo/bar.js", "/bar.js"),
			Entry("unbundle prefixed", "unbundle:@rubygems/foo/bar.js", "/bar.js"),
			Entry("a dot segment", "@rubygems/foo/./bar.js", "/bar.js"),
			Entry("a dot-dot segment that stays inside", "@rubygems/foo/lib/../bar.js", "/bar.js"),
			// esbuild resolves `./lib/` and `./lib` differently when both `lib.js` and
			// `lib/index.js` exist, so the slash that asks for the directory survives cleaning.
			Entry("a directory", "@rubygems/foo/lib/", "/lib/"),
			Entry("a directory reached through a dot-dot segment", "@rubygems/foo/lib/../src/", "/src/"),
		)

		// The URL half of an answer cleans the suffix (GemRef.UrlPath is path.Join) and the file
		// half joins it onto the root as given, so an escaping suffix named one gem in the browser
		// and a directory beside another on disk.
		DescribeTable("refuses a suffix that escapes the gem root",
			func(spec string) {
				ref, isGem, err := utils.GemFromSpecifier(spec, cfg)

				Expect(isGem).To(BeTrue())
				Expect(err).To(MatchError(fmt.Sprintf("%q escapes the root of gem %q", spec, "foo")))
				Expect(ref).To(Equal(utils.GemRef{}))
			},
			Entry("into a sibling", "@rubygems/foo/../bar/x.js"),
			Entry("to the parent", "@rubygems/foo/.."),
			Entry("out and back in", "@rubygems/foo/../foo/x.js"),
			Entry("from below", "@rubygems/foo/lib/../../x.js"),
		)

		// The prefixed forms are the ones that mattered: the old predicate accepted them and the
		// old parser then read the scope as the gem name.
		It("does not mistake the scope for the gem name", func() {
			_, isGem, err := utils.GemFromSpecifier("node_modules/@rubygems/foo/bar.js", cfg)

			Expect(isGem).To(BeTrue())
			Expect(err).NotTo(HaveOccurred())
		})

		It("reports an unbundled gem with the user-facing message", func() {
			ref, isGem, err := utils.GemFromSpecifier("@rubygems/nope/bar.js", cfg)

			Expect(isGem).To(BeTrue(), "it is a gem specifier, just not a bundled one")
			Expect(err).To(MatchError(`could not resolve Ruby gem "nope". Is "nope" in your Gemfile?`))
			Expect(ref).To(Equal(utils.GemRef{}))
		})

		DescribeTable("is not a gem specifier",
			func(spec string) {
				ref, isGem, err := utils.GemFromSpecifier(spec, cfg)

				Expect(isGem).To(BeFalse())
				Expect(err).NotTo(HaveOccurred())
				Expect(ref).To(Equal(utils.GemRef{}))
			},
			Entry("bare module", "lodash/index.js"),
			Entry("another scope", "@scope/pkg/index.js"),
			Entry("the scope alone", "@rubygems/"),
			Entry("relative", "./foo.js"),
			Entry("absolute app path", "/lib/foo.js"),
		)
	})

	Describe("GemFromFsPath", func() {
		DescribeTable("credits the path to the right gem",
			func(fsPath string, name string, root string, suffix string) {
				ref, found := utils.GemFromFsPath(fsPath, cfg)

				Expect(found).To(BeTrue())
				Expect(ref.Name).To(Equal(name))
				Expect(ref.Root).To(Equal(root))
				Expect(ref.Suffix).To(Equal(suffix))
			},
			Entry("inside a root", "/gems/foo/lib/a.js", "foo", "/gems/foo", "/lib/a.js"),
			Entry("the root itself", "/gems/foo", "foo", "/gems/foo", ""),
			// Both of these went to "foo" under the old bare-prefix match.
			Entry("a root sharing a string prefix", "/gems/foo-ext/lib/a.js",
				"foo-ext", "/gems/foo-ext", "/lib/a.js"),
			Entry("a nested root", "/gems/foo/vendor/nested/lib/a.js",
				"nested", "/gems/foo/vendor/nested", "/lib/a.js"),
			Entry("the root and a slash", "/gems/foo/", "foo", "/gems/foo", "/"),
		)

		DescribeTable("is not in any gem",
			func(fsPath string) {
				ref, found := utils.GemFromFsPath(fsPath, cfg)

				Expect(found).To(BeFalse())
				Expect(ref).To(Equal(utils.GemRef{}))
			},
			// No separator boundary, so this was credited to "foo" every single time.
			Entry("a sibling directory sharing a prefix", "/gems/foobar/lib/a.js"),
			Entry("outside every root", "/somewhere/else/a.js"),
			Entry("a prefix of a root", "/gems"),
			// The byte after the root has to be "/". These are one byte past it, and a multibyte
			// character that starts with the same prefix.
			Entry("a root and exactly one more byte", "/gems/foox"),
			Entry("a sibling with a multibyte name", "/gems/foo\u00e9/lib/a.js"),
		)

		// Longest root wins, and a map range visits the roots in a random order, so one call proves
		// little: a first-match-wins lookup gets this right about half the time.
		It("credits a nested root, not the root containing it, whatever the map order", func() {
			for range 40 {
				ref, found := utils.GemFromFsPath("/gems/foo/vendor/nested/lib/a.js", cfg)

				Expect(found).To(BeTrue())
				Expect(ref.Name).To(Equal("nested"))
			}
		})

		// Gem roots may be stored with a trailing separator; the lookup must behave the same.
		It("matches a root stored with a trailing slash", func() {
			slashed := &types.ConfigT{RubyGems: map[string]string{"slashed": "/gems/slashed/"}}

			ref, found := utils.GemFromFsPath("/gems/slashed/lib/a.js", slashed)

			Expect(found).To(BeTrue())
			Expect(ref.Name).To(Equal("slashed"))
			Expect(ref.Root).To(Equal("/gems/slashed/"))
			Expect(ref.Suffix).To(Equal("/lib/a.js"))

			_, found = utils.GemFromFsPath("/gems/slashedother/lib/a.js", slashed)
			Expect(found).To(BeFalse())

			ref, found = utils.GemFromFsPath("/gems/slashed", slashed)
			Expect(found).To(BeTrue())
			Expect(ref.Suffix).To(Equal(""))

			ref, found = utils.GemFromFsPath("/gems/slashed/", slashed)
			Expect(found).To(BeTrue())
			Expect(ref.Suffix).To(Equal("/"))
		})

		// The same directory stored with and without the slash is one root twice, so it is a tie, and
		// the tie is broken on name. Comparing the untrimmed lengths would make it a length contest.
		It("ties a root stored with a slash and the same root without one on name", func() {
			twins := &types.ConfigT{RubyGems: map[string]string{
				"b": "/gems/shared/",
				"a": "/gems/shared",
			}}

			for range 40 {
				ref, found := utils.GemFromFsPath("/gems/shared/lib/x.js", twins)

				Expect(found).To(BeTrue())
				Expect(ref.Name).To(Equal("a"))
			}
		})

		// It runs for every module a build loads, against every gem in Gemfile.lock (not only the gems
		// that ship JS or CSS), and the common case is a path in no gem, which scans them all. It used
		// to build a string per gem per call to test the "/" boundary, so a per-gem allocation was
		// multiplied by hundreds on every module.
		It("does not allocate, whether the path is in a gem or not", func() {
			// Roots must be as long as real install paths. Go builds a short concatenation on the
			// stack, so short roots hide the allocation and this would pass on the old code.
			const installDir = "/Users/someone/.local/share/mise/installs/ruby/3.4.9/lib/ruby/gems/3.4.0/gems"
			Expect(len(installDir)).To(BeNumerically(">", 64))

			gems := make(map[string]string, 300)
			for i := range 300 {
				gems[fmt.Sprintf("gem-%03d", i)] = fmt.Sprintf("%s/gem-%03d-1.2.3", installDir, i)
			}
			many := &types.ConfigT{RubyGems: gems}

			for _, fsPath := range []string{
				"/Users/someone/dev/app/app/javascript/x.js",
				installDir + "/gem-150-1.2.3/lib/x.js",
			} {
				allocs := testing.AllocsPerRun(50, func() { utils.GemFromFsPath(fsPath, many) })

				Expect(allocs).To(BeZero(), fsPath)
			}
		})

		// Two gemspecs can share a source tree, which makes two roots identical. The "/" boundary
		// rules out any other way for two matching roots to have equal length, so this is the only
		// tie there is - and without a tiebreak the winner came from map order (measured 37/3
		// over 40 calls in the function written to remove exactly that).
		It("breaks a tie between two gems sharing a root, deterministically", func() {
			shared := &types.ConfigT{RubyGems: map[string]string{
				"beta":  "/gems/shared",
				"alpha": "/gems/shared",
			}}

			for range 40 {
				ref, found := utils.GemFromFsPath("/gems/shared/lib/x.js", shared)

				Expect(found).To(BeTrue())
				Expect(ref.Name).To(Equal("alpha"))
			}
		})

		// The old lookup ranged a Go map and took the first match, so a path matching two roots
		// was answered inconsistently WITHIN one process - measured at 38/2 and 33/7 over 40
		// calls. Longest-match makes the answer a function of the input alone.
		It("answers the same way every time", func() {
			for range 40 {
				ref, found := utils.GemFromFsPath("/gems/foo-ext/lib/a.js", cfg)

				Expect(found).To(BeTrue())
				Expect(ref.Name).To(Equal("foo-ext"))
			}
		})
	})

	// Both delegate to GemFromFsPath now. Asserted separately because the specs above would pass
	// with the wrappers still doing their own loose prefix match.
	Describe("the filesystem-space wrappers", func() {
		It("PathIsRubyGem credits a prefix-sharing root correctly", func() {
			name, root, found := utils.PathIsRubyGem("/gems/foo-ext/lib/a.js", cfg)

			Expect(found).To(BeTrue())
			Expect(name).To(Equal("foo-ext"))
			Expect(root).To(Equal("/gems/foo-ext"))
		})

		It("PathIsRubyGem does not match across a directory-name boundary", func() {
			_, _, found := utils.PathIsRubyGem("/gems/foobar/lib/a.js", cfg)

			Expect(found).To(BeFalse())
		})

		It("RubyGemPathToUrlPath uses the nested root, not the one containing it", func() {
			urlPath, found := utils.RubyGemPathToUrlPath("/gems/foo/vendor/nested/lib/a.js", cfg)

			Expect(found).To(BeTrue())
			Expect(urlPath).To(Equal("/node_modules/@rubygems/nested/lib/a.js"))
		})
	})

	Describe("UrlPathFromFsPath", func() {
		BeforeEach(func() {
			cfg.RootPath = "/app"
			cfg.RubyGems["vendored"] = "/app/vendor/vendored"
		})

		DescribeTable("names the URL a file is served from",
			func(fsPath string, urlPath string) {
				got, ok := utils.UrlPathFromFsPath(fsPath, cfg)

				Expect(ok).To(BeTrue())
				Expect(got).To(Equal(urlPath))
			},
			Entry("in a gem", "/gems/foo/lib/a.js", "/node_modules/@rubygems/foo/lib/a.js"),
			Entry("in a gem vendored under the app root", "/app/vendor/vendored/x.js",
				"/node_modules/@rubygems/vendored/x.js"),
			Entry("under the app root", "/app/lib/a.js", "/lib/a.js"),
			Entry("the app root itself", "/app", "/"),
		)

		// A missing root would otherwise be a prefix of every path, and the whole point of this
		// function is to be able to say "no".
		It("matches nothing when the app root is empty", func() {
			cfg.RootPath = ""

			got, ok := utils.UrlPathFromFsPath("/app/lib/a.js", cfg)

			Expect(ok).To(BeFalse())
			Expect(got).To(Equal(""))
		})

		// "/" trims to the same empty string as an unset root, and it is a real root: every
		// absolute path is under it, and is its own URL path.
		It("treats the file system root as a root, not as unset", func() {
			cfg.RootPath = "/"

			got, ok := utils.UrlPathFromFsPath("/srv/app/lib/a.js", cfg)

			Expect(ok).To(BeTrue())
			Expect(got).To(Equal("/srv/app/lib/a.js"))
		})

		DescribeTable("has no URL for a file under neither root",
			func(fsPath string) {
				got, ok := utils.UrlPathFromFsPath(fsPath, cfg)

				Expect(ok).To(BeFalse())
				Expect(got).To(Equal(""))
			},
			// A bare prefix match accepted this and answered "-other/x.css".
			Entry("a sibling of the app root", "/app-other/x.css"),
			Entry("a prefix of the app root", "/ap"),
			Entry("outside every root", "/elsewhere/a.js"),
			// Compared as text, so a `..` left in the path walked out of a root that still
			// looked like a prefix: these answered "/../outside.css" and "/vendor/../../x.js".
			Entry("out of the app root through ..", "/app/../outside.css"),
			Entry("out of the app root through .. from below", "/app/lib/../../outside.css"),
			Entry("out of a gem root through ..", "/gems/foo/../../outside.js"),
		)

		It("cleans the path before deciding, and reports the cleaned URL", func() {
			got, ok := utils.UrlPathFromFsPath("/app/lib/../lib/./a.js", cfg)

			Expect(ok).To(BeTrue())
			Expect(got).To(Equal("/lib/a.js"))
		})

		It("matches an app root stored with a trailing slash", func() {
			cfg.RootPath = "/app/"

			got, ok := utils.UrlPathFromFsPath("/app/lib/a.js", cfg)

			Expect(ok).To(BeTrue())
			Expect(got).To(Equal("/lib/a.js"))
		})

		// Through GemFromFsPath, so the longest-root rule applies; looped because a map range
		// visits the roots in a random order.
		It("credits a prefix-sharing gem root the same way every time", func() {
			for range 40 {
				got, ok := utils.UrlPathFromFsPath("/gems/foo-ext/lib/a.js", cfg)

				Expect(ok).To(BeTrue())
				Expect(got).To(Equal("/node_modules/@rubygems/foo-ext/lib/a.js"))
			}
		})

		// A leading "//" is a UNC root on Windows, the form a gem installed on a network share has.
		// path.Clean collapsed it to "/", and the gem roots are compared as given, so a file under
		// one used to match no root at all and went out as a raw filesystem path. Windows only,
		// because elsewhere "//" means "/" and is cleaned to it.
		When("on Windows", func() {
			BeforeEach(func() {
				if runtime.GOOS != "windows" {
					Skip("a UNC root only exists on Windows")
				}
			})

			It("keeps a UNC root, so a gem on a network share still maps to its URL", func() {
				cfg.RubyGems["shared"] = "//server/share/gems/shared"

				got, ok := utils.UrlPathFromFsPath("//server/share/gems/shared/lib/../lib/a.js", cfg)

				Expect(ok).To(BeTrue())
				Expect(got).To(Equal("/node_modules/@rubygems/shared/lib/a.js"))
			})

			It("keeps a UNC app root", func() {
				cfg.RootPath = "//server/share/app"

				got, ok := utils.UrlPathFromFsPath("//server/share/app/lib/a.js", cfg)

				Expect(ok).To(BeTrue())
				Expect(got).To(Equal("/lib/a.js"))
			})
		})

		// Everywhere else a leading "//" is "/", and a path spelled that way is still under the root.
		It("reads a leading // as / outside Windows", func() {
			if runtime.GOOS == "windows" {
				Skip("a leading // is a UNC root on Windows")
			}

			got, ok := utils.UrlPathFromFsPath("//app/lib/a.js", cfg)

			Expect(ok).To(BeTrue())
			Expect(got).To(Equal("/lib/a.js"))
		})
	})

	Describe("GemRef.UrlPath", func() {
		DescribeTable("spells the served URL path",
			func(ref utils.GemRef, expected string) {
				Expect(ref.UrlPath()).To(Equal(expected))
			},
			Entry("with a suffix", utils.GemRef{Name: "foo", Suffix: "/bar.js"},
				"/node_modules/@rubygems/foo/bar.js"),
			Entry("without a suffix", utils.GemRef{Name: "foo"},
				"/node_modules/@rubygems/foo"),
			Entry("with a nested suffix", utils.GemRef{Name: "foo", Suffix: "/lib/bar.js"},
				"/node_modules/@rubygems/foo/lib/bar.js"),
		)
	})
})
