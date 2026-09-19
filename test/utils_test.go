package proscenium_test

import (
	"fmt"
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
