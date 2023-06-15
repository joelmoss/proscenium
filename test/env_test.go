package proscenium_test

import (
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(env)", func() {
	It("replaces with value", func() {
		Expect(Build("lib/env/env.js")).To(ContainCode(`
			console.log("testtest");
		`))
	})

	When("env var is undefined", func() {
		It("is void", func() {
			Expect(Build("lib/env/unknown.js")).To(ContainCode(`
				console.log((void 0).NUFFIN);
				console.log("test");
			`))
		})
	})

	When("used in URL import", func() {
		It("is void", func() {
			MockURL("/foo.js", `console.log(proscenium.env.RAILS_ENV);`)

			Expect(Build("https%3A%2F%2Fproscenium.test%2Ffoo.js")).To(ContainCode(`
				console.log((void 0).RAILS_ENV);
			`))
		})
	})
})
