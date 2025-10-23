package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("BuildToString", func() {
	It("compiles!", func() {
		types.Config.Precompile = []string{
			"./app/models/**/*.js",
			"./app/models/**/*.jsx",
		}

		success, _ := b.Compile()

		Expect(success).To(BeTrue())
	})
})
