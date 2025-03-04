package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("BuildToPath", func() {
	assertCommonBuildBehaviour(b.BuildToPath)

	It("builds js", func() {
		_, result := b.BuildToPath("lib/foo.js")

		Expect(result).To(Equal("lib/foo.js::public/assets/lib/foo$2IXPSM5U$.js"))
	})

	It("builds js from file:* dependency", func() {
		_, result := b.BuildToPath("internal-one-link/index.js")

		Expect(result).To(Equal("internal-one-link/index.js::public/assets/internal-one-link/index$T5LBKH5D$.js"))
	})

	It("builds js from link:* dependency", func() {
		_, result := b.BuildToPath("mypackage/index.js")

		Expect(result).To(Equal("mypackage/index.js::public/assets/mypackage/index$JDMLNL27$.js"))
	})

	It("builds css", func() {
		_, result := b.BuildToPath("lib/foo.css")

		Expect(result).To(Equal("lib/foo.css::public/assets/lib/foo$EAILS7QS$.css"))
	})

	It("supports multiple inputs", func() {
		_, code := b.BuildToPath("lib/code_splitting/son.js;lib/code_splitting/daughter.js")

		Expect(code).To(Equal("lib/code_splitting/son.js::public/assets/lib/code_splitting/son$LAGMAD6O$.js;lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$7JJ2HGHC$.js"))
	})

	When("@rubygems/*", func() {
		It("maps from inside app root", func() {
			addGem("gem1", "dummy/vendor")

			_, code := b.BuildToPath("node_modules/@rubygems/gem1/lib/gem1/gem1.js")

			Expect(code).To(Equal("node_modules/@rubygems/gem1/lib/gem1/gem1.js::public/assets/node_modules/@rubygems/gem1/lib/gem1/gem1$DJKO4NQ6$.js"))
		})

		It("maps from outside app root", func() {
			addGem("gem2", "external")

			_, code := b.BuildToPath("node_modules/@rubygems/gem2/lib/gem2/gem2.js")

			Expect(code).To(Equal("node_modules/@rubygems/gem2/lib/gem2/gem2.js::public/assets/node_modules/@rubygems/gem2/lib/gem2/gem2$HVOJOFHK$.js"))
		})

		It("should return input > output mapping", func() {
			addGem("gem1", "dummy/vendor")
			addGem("gem2", "external")
			addGem("gem3", "dummy/vendor")
			addGem("gem4", "external")

			_, code := b.BuildToPath("node_modules/@rubygems/gem4/lib/gem4/gem4.js;lib/gems/gem3.js;lib/foo.css")

			Expect(code).To(Equal("node_modules/@rubygems/gem4/lib/gem4/gem4.js::public/assets/node_modules/@rubygems/gem4/lib/gem4/gem4$B6JZL62F$.js;lib/gems/gem3.js::public/assets/lib/gems/gem3$QB4NOOOT$.js;lib/foo.css::public/assets/lib/foo$EAILS7QS$.css"))
		})
	})
})

func BenchmarkBuildToPath(bm *testing.B) {
	bm.ResetTimer()

	for i := 0; i < bm.N; i++ {
		success, result := b.BuildToPath("lib/foo.js")

		if !success {
			panic("Build failed: " + result)
		}
	}
}
