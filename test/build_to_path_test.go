package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"path/filepath"
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
			types.Config.RubyGems = map[string]string{
				"gem1": filepath.Join(fixturesRoot, "dummy", "vendor", "gem1"),
			}

			_, code := b.BuildToPath("node_modules/@rubygems/gem1/lib/gem1/gem1.js")

			Expect(code).To(Equal("node_modules/@rubygems/gem1/lib/gem1/gem1.js::public/assets/node_modules/@rubygems/gem1/lib/gem1/gem1$DJKO4NQ6$.js"))
		})

		It("maps from outside app root", func() {
			types.Config.RubyGems = map[string]string{
				"gem2": filepath.Join(fixturesRoot, "external", "gem2"),
			}

			_, code := b.BuildToPath("node_modules/@rubygems/gem2/lib/gem2/gem2.js")

			Expect(code).To(Equal("node_modules/@rubygems/gem2/lib/gem2/gem2.js::public/assets/node_modules/@rubygems/gem2/lib/gem2/gem2$HVOJOFHK$.js"))
		})

		It("should return input > output mapping", func() {
			types.Config.RubyGems = map[string]string{
				"gem1": filepath.Join(fixturesRoot, "dummy", "vendor", "gem1"),
				"gem2": filepath.Join(fixturesRoot, "external", "gem2"),
				"gem3": filepath.Join(fixturesRoot, "dummy", "vendor", "gem3"),
				"gem4": filepath.Join(fixturesRoot, "external", "gem4"),
			}

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
