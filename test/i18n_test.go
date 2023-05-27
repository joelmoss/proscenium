package proscenium_test

import (
	. "joelmoss/proscenium/test/support"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(i18n)", func() {
	It("exports json", func() {
		Expect(Build("lib/i18n/benchmark/index.js")).To(ContainCode(`
			{ first_name: "Joel", foo: { bar: { baz: 1 } }, last_name: "Moss" }
		`))
	})
})

// Avg 875,000 ns/op
func BenchmarkI18n(b *testing.B) {
	b.ResetTimer()

	for i := 0; i < b.N; i++ {
		result := Build("lib/i18n/benchmark/index.js")

		if len(result.Errors) > 0 {
			panic("Build failed: " + result.Errors[0].Text)
		}
	}
}
