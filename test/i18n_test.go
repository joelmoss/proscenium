package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/test/support"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.BuildToString(i18n)", func() {
	It("exports json", func() {
		_, code, _ := b.BuildToString("lib/i18n/benchmark/index.js")

		Expect(code).To(ContainCode(`
			{ firstName: "Joel", foo: { bar: { baz: 1 } }, lastName: "Moss" }
		`))
	})
})

// Avg 875,000 ns/op
func BenchmarkI18n(bm *testing.B) {
	bm.ResetTimer()

	for i := 0; i < bm.N; i++ {
		success, result, _ := b.BuildToString("lib/i18n/benchmark/index.js")

		if !success {
			panic("Build failed: " + result)
		}
	}
}
