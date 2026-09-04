package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/test/support"
	"regexp"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.BuildToString(svg)", func() {
	svgContent := `
		<svg aria-hidden="true" focusable="false" role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="currentColor" d="M504"></path></svg>
	`

	EntryPoint("lib/svg/absolute_jsx.jsx", func() {
		AssertCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`)
	})

	EntryPoint("lib/svg/absolute_tsx.tsx", func() {
		AssertCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`)
	})

	EntryPoint("lib/svg/relative.jsx", func() {
		AssertCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`)
	})

	EntryPoint("lib/svg/bare.jsx", func() {
		AssertCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`)
	})

	When("Bundle = false", func() {
		BeforeEach(func() {
			testConfig.Bundle = false
		})

		// An SVG imported from JS(X) is loaded even when unbundling, because the JS side needs the
		// wrapped component. Externalising it would hand raw XML to the JS runtime.
		It("wraps an svg imported from jsx as a component", func() {
			_, code, _ := b.BuildToString("lib/svg/absolute_jsx.jsx", testConfig)

			Expect(code).To(ContainCode(`("svg"`))
			Expect(code).NotTo(ContainCode(`from "/public/at.svg"`))
		})

		It("wraps an svg imported from tsx as a component", func() {
			_, code, _ := b.BuildToString("lib/svg/absolute_tsx.tsx", testConfig)

			Expect(code).To(ContainCode(`("svg"`))
			Expect(code).NotTo(ContainCode(`from "/public/at.svg"`))
		})

		It("wraps an svg imported by bare specifier as a component", func() {
			_, code, _ := b.BuildToString("lib/svg/bare.jsx", testConfig)

			Expect(code).To(ContainCode(`("svg"`))
			Expect(code).NotTo(ContainCode(`from "/node_modules/pkg/at.svg"`))
		})

		It("wraps an svg imported by relative path as a component", func() {
			_, code, _ := b.BuildToString("lib/svg/relative.jsx", testConfig)

			Expect(code).To(ContainCode(`("svg"`))
		})

		// Regressions. Only an SVG imported from JSX/TSX changes; every other svg import that was
		// externalised when unbundling stays externalised.
		It("leaves an svg imported from plain js external", func() {
			_, code, _ := b.BuildToString("lib/svg/plain_js.js", testConfig)

			Expect(code).To(ContainCode(`import AtIcon from "/public/at.svg";`))
		})

		It("leaves an svg referenced from css external", func() {
			_, code, _ := b.BuildToString("lib/svg/svg.css", testConfig)

			Expect(code).To(ContainCode(`url(/hue/icons/angle-right-regular.svg)`))
		})
	})

	Context("internal @rubygems/*", func() {
		BeforeEach(func() {
			addGem("gem1", "dummy/vendor")
		})

		It("bundles", func() {
			_, code, _ := b.BuildToString("lib/svg/internal_rubygem.jsx", testConfig)

			Expect(code).To(ContainCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
			Expect(code).NotTo(ContainCode(`import AtIcon from "@rubygems/gem1/at.svg";`))
		})

		It("resolves, but does not bundle from css", func() {
			_, code, _ := b.BuildToString("lib/svg/internal_rubygem.css", testConfig)

			Expect(code).To(ContainCode(`
				url(/node_modules/@rubygems/gem1/at.svg)`,
			))
		})
	})

	Context("external @rubygems/*", func() {
		BeforeEach(func() {
			addGem("gem2", "external")
		})

		It("bundles", func() {
			_, code, _ := b.BuildToString("lib/svg/external_rubygem.jsx", testConfig)

			Expect(code).To(ContainCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
			Expect(code).NotTo(ContainCode(`import AtIcon from "@rubygems/gem2/at.svg";`))
		})

		It("resolves, but does not bundle from css", func() {
			_, code, _ := b.BuildToString("lib/svg/external_rubygem.css", testConfig)

			Expect(code).To(ContainCode(`
				url(/node_modules/@rubygems/gem2/at.svg)`,
			))
		})
	})

	It("does not bundle svg from css", func() {
		_, code, _ := b.BuildToString("lib/svg/svg.css", testConfig)

		Expect(code).To(ContainCode(`
			url(/hue/icons/angle-right-regular.svg)`,
		))
	})

	It("bundles remote svg from jsx", func() {
		MockURL("/at.svg", svgContent)

		_, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

		Expect(code).To(ContainCode(`
			var svg = /* @__PURE__ */ jsx("svg", { "aria-hidden": "true", focusable: "false", role: "img", xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 512 512", children: /* @__PURE__ */ jsx("path", { fill: "currentColor", d: "M504" }) });
		`))
	})

	When("importing remote svg from css", func() {
		PIt("should not bundle or encode; leave as is", func() {
			var re = regexp.MustCompile(`^https?://.+(^\.svg)`)
			Expect(re.MatchString("https://sdfsdf.jsvg")).To(BeTrue())
		})

		PIt("should not bundle or encode; leave as is", func() {
			MockURL("/at.svg", svgContent)

			_, code, _ := b.BuildToString("lib/svg/remote.css", testConfig)

			Expect(code).To(ContainCode(`background-image: url(https://proscenium.test/at.svg);`))
		})
	})
})
