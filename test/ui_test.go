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
			"proscenium": types.Config.GemPath + "/lib/proscenium/ui",
		}
	})

	When("Bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
		})

		It("fails to build @proscenium/*", func() {
			result := b.Build("@proscenium/test.js")
			Expect(result.Errors[0].Text).To(Equal("Could not resolve \"@proscenium/test.js\""))
		})

		It("builds proscenium/*", func() {
			Expect(b.Build("proscenium/test.js")).To(ContainCode(`
				console.log("proscenium/test.js");
			`))
		})

		It("builds proscenium/ujs", func() {
			Expect(b.Build("proscenium/ujs")).To(ContainCode(`
				const classPath = "/proscenium/ujs/class.js";
			`))
		})

		It("builds without file extension", func() {
			Expect(b.Build("proscenium/test")).To(ContainCode(`
				console.log("proscenium/test.js");
			`))
		})

		It("does not bundle imports", func() {
			Expect(b.Build("lib/ui/test.js")).To(ContainCode(`
				import "/proscenium/test.js";
			`))
		})

		It("resolves proscenium/stimulus-loading", func() {
			Expect(b.Build("proscenium/stimulus-loading")).To(ContainCode(`
				function lazyLoadControllersFrom
			`))
		})

		It("resolves proscenium/custom_element", func() {
			Expect(b.Build("proscenium/custom_element")).To(ContainCode(`
				var CustomElement = class extends HTMLElement {
			`))
		})

		It("resolves imports", func() {
			Expect(b.Build("proscenium/ujs/class.js")).To(ContainCode(`
				import DataConfirm from "/proscenium/ujs/data_confirm.js";
				import DataDisableWith from "/proscenium/ujs/data_disable_with.js";
			`))
		})

		It("BuildToPath", func() {
			_, code := b.BuildToPath("proscenium/ujs/class.js")
			Expect(code).To(Equal(`proscenium/ujs/class.js::public/assets/proscenium/ujs/class$W4C7O333$.js`))
		})

		It("BuildToString", func() {
			_, code := b.BuildToString("proscenium/test.js")
			Expect(code).To(ContainCode(`console.log("proscenium/test.js");`))
		})
	})

	When("Bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
		})

		It("builds proscenium/*", func() {
			Expect(b.Build("proscenium/test.js")).To(ContainCode(`
				console.log("proscenium/test.js");
			`))
		})

		It("builds proscenium/ujs", func() {
			Expect(b.Build("proscenium/ujs")).To(ContainCode(`
				const classPath = "/proscenium/ujs/class.js";
			`))
		})

		It("builds without file extension", func() {
			Expect(b.Build("proscenium/test")).To(ContainCode(`
				console.log("proscenium/test.js");
			`))
		})

		It("bundles imports", func() {
			Expect(b.Build("lib/ui/test.js")).To(ContainCode(`
				console.log("proscenium/test.js");
			`))
		})

		It("resolves proscenium/stimulus-loading", func() {
			Expect(b.Build("proscenium/stimulus-loading")).To(ContainCode(`
				function lazyLoadControllersFrom
			`))
		})
	})
})
