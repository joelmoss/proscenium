package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/test/support"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.Build(i18n)", func() {
	It("exports json", func() {
		Expect(b.Build("lib/i18n/benchmark/index.js")).To(ContainCode(`
			{ first_name: "Joel", foo: { bar: { baz: 1 } }, last_name: "Moss" }
		`))
	})
})

// Avg 875,000 ns/op
func BenchmarkI18n(bm *testing.B) {
	bm.ResetTimer()

	for i := 0; i < bm.N; i++ {
		result := b.Build("lib/i18n/benchmark/index.js")

		if len(result.Errors) > 0 {
			panic("Build failed: " + result.Errors[0].Text)
		}
	}
}
