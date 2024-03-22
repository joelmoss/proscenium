package proscenium_test

import (
	. "joelmoss/proscenium/test/support"
	"regexp"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(svg)", func() {
	svgContent := `
		<svg aria-hidden="true" focusable="false" role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="currentColor" d="M504"></path></svg>
	`

	When("importing absolute svg from jsx", func() {
		It("bundles", func() {
			result := Build("lib/svg/absolute.jsx")

			Expect(result).To(ContainCode(`svg = /* @__PURE__ */ jsx("svg"`))
			Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
		})
	})

	When("importing svg from tsx", func() {
		It("bundles", func() {
			result := Build("lib/svg/absolute.tsx")

			Expect(result).To(ContainCode(`svg = /* @__PURE__ */ jsx("svg"`))
			Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
		})
	})

	When("importing relative svg from jsx", func() {
		It("bundles", func() {
			result := Build("lib/svg/relative.jsx")

			Expect(result).To(ContainCode(`svg = /* @__PURE__ */ jsx("svg"`))
			Expect(result).NotTo(ContainCode(`import AtIcon from "/lib/svg/at.svg";`))
		})
	})

	When("importing bare svg specifier from jsx", func() {
		It("bundles", func() {
			result := Build("lib/svg/bare.jsx")

			Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
			Expect(result).To(ContainCode(`var svg = /* @__PURE__ */ jsx("svg"`))
		})
	})

	When("importing svg from css", func() {
		It("should not bundle", func() {
			Expect(Build("lib/svg.css")).To(ContainCode(`
					url(/hue/icons/angle-right-regular.svg)`,
			))
		})
	})

	When("importing remote svg from jsx", func() {
		It("should bundle", func() {
			MockURL("/at.svg", svgContent)

			result := Build("lib/svg/remote.jsx")

			Expect(result).To(ContainCode(`
					var svg = /* @__PURE__ */ jsx("svg", { "aria-hidden": "true", focusable: "false", role: "img", xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 512 512", children: /* @__PURE__ */ jsx("path", { fill: "currentColor", d: "M504" }) });
				`))
		})
	})

	When("importing remote svg from css", func() {
		PIt("should not bundle or encode; leave as is", func() {
			var re = regexp.MustCompile(`^https?://.+(^\.svg)`)
			Expect(re.MatchString("https://sdfsdf.jsvg")).To(BeTrue())
		})

		PIt("should not bundle or encode; leave as is", func() {
			MockURL("/at.svg", svgContent)

			result := Build("lib/svg/remote.css")

			Expect(result).To(ContainCode(`background-image: url(https://proscenium.test/at.svg);`))
		})
	})
})
