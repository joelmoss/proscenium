package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/test/support"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("BuildToString", func() {
	It("should fail on unknown entrypoint", func() {
		success, result := b.BuildToString("unknown.js")

		Expect(success).To(BeFalse())
		Expect(result).To(Equal("{\"ID\":\"\",\"PluginName\":\"\",\"Text\":\"Could not resolve \\\"unknown.js\\\"\",\"Location\":null,\"Notes\":null,\"Detail\":null}"))
	})

	It("should build js", func() {
		_, result := b.BuildToString("lib/foo.js")
		Expect(result).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("should return source map", func() {
		_, result := b.BuildToString("lib/foo.js.map")
		Expect(result).To(ContainCode(`
			"sources": ["../../../lib/foo.js"],
			"sourcesContent": ["console.log('/lib/foo.js')\n"],
		`))
	})

	It("should append source map location for js", func() {
		_, result := b.BuildToString("lib/foo.js")
		Expect(result).To(ContainCode("//# sourceMappingURL=foo.js.map"))
	})

	It("should append source map location for css", func() {
		_, result := b.BuildToString("lib/foo.css")
		Expect(result).To(ContainCode("/*# sourceMappingURL=foo.css.map */"))
	})
})

func BenchmarkBuildToString(bm *testing.B) {
	bm.ResetTimer()

	for i := 0; i < bm.N; i++ {
		success, result := b.BuildToString("lib/foo.js")

		if !success {
			panic("Build failed: " + result)
		}
	}
}
