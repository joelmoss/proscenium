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
