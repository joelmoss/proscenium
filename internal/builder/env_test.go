package builder_test

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	. "joelmoss/proscenium/internal/testing"
	"joelmoss/proscenium/internal/types"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/env", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		plugin.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	It("exports requested env var as default", func() {
		Expect(Build("lib/env/rails_env.js")).To(ContainCode(`
			var RAILS_ENV_default = "test";
		`))
	})

	When("bundling", func() {
		It("exports requested env var as default", func() {
			Expect(Build("lib/env/rails_env.js", BuildOpts{Bundle: true})).To(ContainCode(`
				var RAILS_ENV_default = "test";
			`))
		})
	})

	When("env var is not set", func() {
		It("exports undefined", func() {
			Expect(Build("lib/env/undefined_env.js")).To(ContainCode(`
				var UNDEF_default = UNDEF;
			`))
		})

		When("bundling", func() {
			It("exports undefined", func() {
				Expect(Build("lib/env/undefined_env.js", BuildOpts{Bundle: true})).To(ContainCode(`
					var UNDEF_default = UNDEF;
				`))
			})
		})
	})
})
