package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.Build(ui)", func() {
	BeforeEach(func() {
		types.Config.Engines = map[string]string{
			"proscenium/ui": types.Config.GemPath + "/lib/proscenium/ui",
		}
	})

	When("Bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
		})

		It("fails to build @proscenium/*", func() {
			result := b.Build("@proscenium/ui/test.js")
			Expect(result.Errors[0].Text).To(Equal("Could not resolve \"@proscenium/ui/test.js\""))
		})

		It("builds proscenium/ui", func() {
			Expect(b.Build("proscenium/ui/test.js")).To(ContainCode(`
				console.log("proscenium/ui/test.js");
			`))
		})

		It("builds proscenium/ujs", func() {
			Expect(b.Build("proscenium/ujs")).To(ContainCode(`
				const classPath = "/proscenium/ui/ujs/class.js";
			`))
		})

		It("builds without file extension", func() {
			Expect(b.Build("proscenium/ui/test")).To(ContainCode(`
				console.log("proscenium/ui/test.js");
			`))
		})

		It("does not bundle imports", func() {
			Expect(b.Build("lib/ui/test.js")).To(ContainCode(`
				import "/proscenium/ui/test.js";
			`))
		})

		It("resolves proscenium/stimulus-loading", func() {
			Expect(b.Build("proscenium/stimulus-loading")).To(ContainCode(`
				function lazyLoadControllersFrom
			`))
		})

		It("resolves imports", func() {
			Expect(b.Build("proscenium/ujs/class.js")).To(ContainCode(`
				import DataConfirm from "/proscenium/ui/ujs/data_confirm.js";
				import DataDisableWith from "/proscenium/ui/ujs/data_disable_with.js";
			`))
		})

		It("BuildToPath", func() {
			_, code := b.BuildToPath("proscenium/ui/ujs/class.js")
			Expect(code).To(Equal(`proscenium/ui/ujs/class.js::public/assets/proscenium/ui/ujs/class$5IN4F65N$.js`))
		})
	})

	When("Bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
		})

		It("builds proscenium/ui", func() {
			Expect(b.Build("proscenium/ui/test.js")).To(ContainCode(`
				console.log("proscenium/ui/test.js");
			`))
		})

		It("builds proscenium/ujs", func() {
			Expect(b.Build("proscenium/ujs")).To(ContainCode(`
				const classPath = "/proscenium/ui/ujs/class.js";
			`))
		})

		It("bundles imports", func() {
			Expect(b.Build("lib/ui/test.js")).To(ContainCode(`
				console.log("proscenium/ui/test.js");
			`))
		})

		It("builds without file extension", func() {
			Expect(b.Build("proscenium/ui/test")).To(ContainCode(`
				console.log("proscenium/ui/test.js");
			`))
		})

		It("resolves proscenium/stimulus-loading", func() {
			Expect(b.Build("proscenium/stimulus-loading")).To(ContainCode(`
				function lazyLoadControllersFrom
			`))
		})
	})
})
