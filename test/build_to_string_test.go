package proscenium_test

import (
	. "joelmoss/proscenium/test/support"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("BuildToString", func() {
	It("should fail on unknown entrypoint", func() {
		success, result := BuildToString("unknown.js")

		Expect(success).To(BeFalse())
		Expect(result).To(Equal("{\"ID\":\"\",\"PluginName\":\"\",\"Text\":\"Could not resolve \\\"unknown.js\\\"\",\"Location\":null,\"Notes\":null,\"Detail\":null}"))
	})

	It("should build js", func() {
		_, result := BuildToString("lib/foo.js")
		Expect(result).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("should return source map", func() {
		_, result := BuildToString("lib/foo.js.map")
		Expect(result).To(ContainCode(`
			"sources": ["../../../lib/foo.js"],
			"sourcesContent": ["console.log('/lib/foo.js')\n"],
		`))
	})

	It("should append source map location for js", func() {
		_, result := BuildToString("lib/foo.js")
		Expect(result).To(ContainCode("//# sourceMappingURL=foo.js.map"))
	})

	It("should append source map location for css", func() {
		_, result := BuildToString("lib/foo.css")
		Expect(result).To(ContainCode("/*# sourceMappingURL=foo.css.map */"))
	})

	When("multiple inputs", func() {
		It("should return input > output mapping", func() {
			_, code := BuildToString("lib/code_splitting/son.js;lib/code_splitting/daughter.js")

			Expect(code).To(Equal("lib/code_splitting/son.js::public/assets/lib/code_splitting/son$7CNKRT3J$.js;lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$P5YYU4WE$.js"))
		})
	})
})

func BenchmarkBuildToString(b *testing.B) {
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		success, result := BuildToString("lib/foo.js")

		if !success {
			panic("Build failed: " + result)
		}
	}
}
