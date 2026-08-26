package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("BuildToString", func() {
	It("compiles!", func() {
		testConfig.Precompile = []string{
			"./app/models/**/*.js",
			"./app/models/**/*.jsx",
		}

		success, _ := b.Compile(testConfig)

		Expect(success).To(BeTrue())
	})

	It("handles css modules", func() {
		testConfig.Precompile = []string{
			"./app/components/css_module_import.js",
			"./app/components/css_module_import.module.css",
		}

		success, _ := b.Compile(testConfig)

		Expect(success).To(BeTrue())
	})
})
