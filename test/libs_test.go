package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.Build(Libs)", func() {
	BeforeEach(func() {
		types.Config.Engines = map[string]string{
			"proscenium": types.Config.GemPath,
		}
	})

	When("Bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
		})

		It("builds from lib/libs", func() {
			Expect(b.Build("@proscenium/test.js")).To(ContainCode(`
				console.log("/@proscenium/test.js");
			`))

			Expect(b.Build("@proscenium/ujs")).To(ContainCode(`
				const classPath = "/@proscenium/ujs/class.js";
			`))
		})

		It("builds without file extension", func() {
			Expect(b.Build("@proscenium/ujs/class")).To(ContainCode(`
				import DataConfirm from "/proscenium/lib/proscenium/libs/ujs/data_confirm.js";
				import DataDisableWith from "/proscenium/lib/proscenium/libs/ujs/data_disable_with.js";
			`))
		})

		It("builds with file extension", func() {
			Expect(b.Build("@proscenium/ujs/class.js")).To(ContainCode(`
				import DataConfirm from "/proscenium/lib/proscenium/libs/ujs/data_confirm.js";
				import DataDisableWith from "/proscenium/lib/proscenium/libs/ujs/data_disable_with.js";
			`))
		})

		It("builds to path", func() {
			_, code := b.BuildToPath("@proscenium/test.js")
			Expect(code).To(Equal("@proscenium/test.js::public/assets/@proscenium/test$SLCFI4GA$.js"))
		})
	})

	When("Bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
		})

		It("builds from lib/libs", func() {
			Expect(b.Build("@proscenium/test.js")).To(ContainCode(`
				console.log("/@proscenium/test.js");
			`))

			Expect(b.Build("@proscenium/ujs")).To(ContainCode(`
				const classPath = "/@proscenium/ujs/class.js";
			`))
		})

		It("builds to path", func() {
			_, code := b.BuildToPath("@proscenium/test.js")
			Expect(code).To(Equal("@proscenium/test.js::public/assets/@proscenium/test$SLCFI4GA$.js"))
		})
	})
})
