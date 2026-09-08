package proscenium_test

import (
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
		)

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
