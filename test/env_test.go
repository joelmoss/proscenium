package proscenium_test

import (
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(env)", func() {
	It("exports requested env var as default", func() {
		Expect(Build("lib/env/rails_env.js")).To(ContainCode(`
			var RAILS_ENV_default = "test";
		`))
	})

	When("env var is not set", func() {
		It("exports undefined", func() {
			Expect(Build("lib/env/undefined_env.js")).To(ContainCode(`
				var UNDEF_default = void 0;
			`))
		})
	})
})
