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

	It("builds js from pnpm file:* dependency", func() {
		_, result := b.BuildToPath("pnpm-file/one.js")

		Expect(result).To(Equal("pnpm-file/one.js::public/assets/pnpm-file/one$V3PJMJRZ$.js"))
	})

	It("builds js from pnpm external file:* dependency", func() {
		_, result := b.BuildToPath("pnpm-file-ext/one.js")

		Expect(result).To(Equal("pnpm-file-ext/one.js::public/assets/pnpm-file-ext/one$4JUTPGX6$.js"))
	})

	It("builds js from pnpm link:* dependency", func() {
		_, result := b.BuildToPath("pnpm-link/one.js")

		Expect(result).To(Equal("pnpm-link/one.js::public/assets/pnpm-link/one$KMEURR4J$.js"))
	})

	It("builds js from pnpm external link:* dependency", func() {
		_, result := b.BuildToPath("pnpm-link-ext/one.js")

		Expect(result).To(Equal("pnpm-link-ext/one.js::public/assets/pnpm-link-ext/one$BPTB7ZPN$.js"))
	})

	It("builds css", func() {
		_, result := b.BuildToPath("lib/foo.css")

		Expect(result).To(Equal("lib/foo.css::public/assets/lib/foo$EAILS7QS$.css"))
	})

	It("builds jsx", func() {
		_, result := b.BuildToPath("lib/foo.jsx")

		Expect(result).To(Equal("lib/foo.jsx::public/assets/lib/foo$XPYH4355$.js"))
	})

	// FIt("builds css module", func() {
	// 	types.Config.UseDevCSSModuleNames = true
	// 	addGem("gem_npm", "dummy/vendor")

	// 	_, result := b.BuildToPath("node_modules/@rubygems/gem_npm/index.module.css")

	// 	Expect(result).To(Equal("lib/foo.css::public/assets/lib/foo$EAILS7QS$.css"))
	// })

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

		XIt("maps jsx from outside app root", func() {
			addGem("gem2", "external")

			_, code := b.BuildToPath("node_modules/@rubygems/gem2/lib/gem2/foo.jsx")

			Expect(code).To(Equal("node_modules/@rubygems/gem2/lib/gem2/gem2.jsx::public/assets/node_modules/@rubygems/gem2/lib/gem2/gem2$HVOJOFHK$.js"))
		})

		It("should return input > output mapping", func() {
			addGem("gem1", "dummy/vendor")
			addGem("gem2", "external")
			addGem("gem3", "dummy/vendor")
			addGem("gem4", "external")

			_, code := b.BuildToPath("node_modules/@rubygems/gem4/lib/gem4/gem4.js;lib/gems/gem3.js;lib/foo.css")

			Expect(code).To(Equal("node_modules/@rubygems/gem4/lib/gem4/gem4.js::public/assets/node_modules/@rubygems/gem4/lib/gem4/gem4$VAEWVYS2$.js;lib/gems/gem3.js::public/assets/lib/gems/gem3$TUX2ZVLS$.js;lib/foo.css::public/assets/lib/foo$EAILS7QS$.css"))
		})

		It("resolves from file:* npm install", func() {
			addGem("gem_file", "dummy/vendor")

			_, code := b.BuildToPath("node_modules/@rubygems/gem_file/index.module.css")

			Expect(code).To(Equal("node_modules/@rubygems/gem_file/index.module.css::public/assets/node_modules/@rubygems/gem_file/index.module$MU534OS6$.css"))
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
