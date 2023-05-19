package builder_test

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	. "joelmoss/proscenium/internal/testing"
	"joelmoss/proscenium/internal/types"
	"testing"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/i18n", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		plugin.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	It("exports json", func() {
		Expect(Build("@proscenium/i18n")).To(ContainCode(`
			{ first_name: "Joel", foo: { bar: { baz: 1 } }, last_name: "Moss" }
		`))
	})
})

func BenchmarkI18n(b *testing.B) {
	for i := 0; i < b.N; i++ {
		Build("@proscenium/i18n")
	}
}
