package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.Build(env)", func() {
	It("replaces with value", func() {
		Expect(b.Build("lib/env/env.js")).To(ContainCode(`
			console.log("testtest");
		`))
	})

	When("env var is undefined", func() {
		It("is void", func() {
			Expect(b.Build("lib/env/unknown.js")).To(ContainCode(`
				console.log((void 0).NUFFIN);
				console.log("test");
			`))
		})
	})
})
