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
	It("should fail on unknown entrypoint", func() {
		success, result := b.BuildToPath("unknown.js")

		Expect(success).To(BeFalse())
		Expect(result).To(Equal("{\"ID\":\"\",\"PluginName\":\"\",\"Text\":\"Could not resolve \\\"unknown.js\\\"\",\"Location\":null,\"Notes\":null,\"Detail\":null}"))
	})

	It("should build js", func() {
		_, result := b.BuildToPath("lib/foo.js")
		Expect(result).To(Equal(`lib/foo.js::public/assets/lib/foo$2IXPSM5U$.js`))
	})

	When("multiple inputs", func() {
		It("should return input > output mapping", func() {
			_, code := b.BuildToPath("lib/code_splitting/son.js;lib/code_splitting/daughter.js")

			Expect(code).To(Equal("lib/code_splitting/son.js::public/assets/lib/code_splitting/son$LAGMAD6O$.js;lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$7JJ2HGHC$.js"))
		})
	})

	When("from engine", func() {
		It("should return input > output mapping", func() {
			types.Config.Engines = map[string]string{
				"gem3": filepath.Join(fixturesRoot, "dummy", "vendor", "gem3"),
				"gem4": filepath.Join(fixturesRoot, "external", "gem4"),
			}

			_, code := b.BuildToPath("gem4/lib/gem4/gem4.js;lib/gems/gem3.js;lib/foo.css")

			Expect(code).To(Equal("gem4/lib/gem4/gem4.js::public/assets/gem4/lib/gem4/gem4$YQBH44X7$.js;lib/gems/gem3.js::public/assets/lib/gems/gem3$BPCGTVQJ$.js;lib/foo.css::public/assets/lib/foo$EAILS7QS$.css"))
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
