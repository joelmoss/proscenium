package proscenium_test

import (
	. "joelmoss/proscenium/test/support"
	"path/filepath"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("BuildToPath", func() {
	It("should fail on unknown entrypoint", func() {
		success, result := BuildToPath("unknown.js")

		Expect(success).To(BeFalse())
		Expect(result).To(Equal("{\"ID\":\"\",\"PluginName\":\"\",\"Text\":\"Could not resolve \\\"unknown.js\\\"\",\"Location\":null,\"Notes\":null,\"Detail\":null}"))
	})

	It("should build js", func() {
		_, result := BuildToPath("lib/foo.js")
		Expect(result).To(Equal(`lib/foo.js::public/assets/lib/foo$2IXPSM5U$.js`))
	})

	When("multiple inputs", func() {
		It("should return input > output mapping", func() {
			_, code := BuildToPath("lib/code_splitting/son.js;lib/code_splitting/daughter.js")

			Expect(code).To(Equal("lib/code_splitting/son.js::public/assets/lib/code_splitting/son$7CNKRT3J$.js;lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$P5YYU4WE$.js"))
		})
	})

	When("from engine", func() {
		It("should return input > output mapping", func() {
			_, code := BuildToPath("gem4/lib/gem4/gem4.js;lib/gems/gem3.js;lib/foo.css", BuildOpts{
				Engines: map[string]string{
					"gem3": filepath.Join(fixturesRoot, "dummy", "vendor", "gem3"),
					"gem4": filepath.Join(fixturesRoot, "external", "gem4"),
				},
			})

			Expect(code).To(Equal("gem4/lib/gem4/gem4.js::public/assets/gem4/lib/gem4/gem4$QRM5CHR3$.js;lib/gems/gem3.js::public/assets/lib/gems/gem3$3QHNKL53$.js;lib/foo.css::public/assets/lib/foo$EAILS7QS$.css"))
		})
	})
})

func BenchmarkBuildToPath(b *testing.B) {
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		success, result := BuildToString("lib/foo.js")

		if !success {
			panic("Build failed: " + result)
		}
	}
}
