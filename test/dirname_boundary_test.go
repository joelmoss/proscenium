package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// The app root has to match at a "/" boundary, and `fixtures/dummy-sibling` is the case that
// proves it: it begins with the root's own path, so a bare prefix trim accepts it.
//
// The dirname plugin used to do exactly that (`strings.CutPrefix(args.Path, cfg.RootPath)`) and
// handed this file `__filename = "-sibling/sibling.js"` - a path that resolves to nothing, in
// code that ships to the browser. It now goes through `utils.UrlPathFromFsPath`, which requires
// the boundary and reports "not under any root" instead.
//
// Both wrong answers are asserted against, because the fix has two ways to go wrong: keeping the
// boundary-less trim, and migrating without handling the "not found" answer - the second gives
// `__filename = ""`, which is not obviously wrong when read in the output.
var _ = Describe("the app root boundary, through the dirname plugin", func() {
	It("gives no __filename to a file in a sibling directory sharing the root's name", func() {
		success, code, _ := b.BuildToString("lib/dirname_sibling.js", testConfig)

		Expect(success).To(BeTrue(), code)

		// The file is in the bundle, so the build did reach it and the dirname plugin did run
		// against it. Without this the two assertions below would pass on an empty build.
		Expect(code).To(ContainSubstring("siblingFilename"))

		// Asserted as substrings rather than through ContainCode: what is being ruled out is one
		// exact string in a declaration esbuild has already rewritten, not a code shape.
		Expect(code).NotTo(ContainSubstring(`"-sibling/sibling.js"`),
			"the root was trimmed with no boundary, so a sibling directory looked like it was inside it")
		Expect(code).NotTo(ContainSubstring(`__filename = ""`),
			"the path is under no root, and that answer was used instead of being handled")
	})

	// The other side of the same boundary: a file genuinely under the root still gets its path.
	It("still gives __filename to a file under the root", func() {
		success, code, _ := b.BuildToString("lib/dirname_test.js", testConfig)

		Expect(success).To(BeTrue(), code)
		Expect(code).To(ContainCode(`"/lib/dirname_test.js"`))
	})
})
