package builder_test

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	. "joelmoss/proscenium/internal/testing"
	"joelmoss/proscenium/internal/types"
	"regexp"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/svg", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		plugin.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	svgContent := `
		<svg aria-hidden="true" focusable="false" role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="currentColor" d="M504"></path></svg>
	`

	When("importing absolute svg from jsx", func() {
		It("bundles", func() {
			result := Build("lib/svg/absolute.jsx")

			Expect(result).To(ContainCode(`svg = /* @__PURE__ */ jsx("svg"`))
			Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
		})

		When("bundling", func() {
			It("bundles", func() {
				result := Build("lib/svg/absolute.jsx", BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
				Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
			})
		})
	})

	When("importing relative svg from jsx", func() {
		It("bundles", func() {
			result := Build("lib/svg/relative.jsx")

			Expect(result).To(ContainCode(`svg = /* @__PURE__ */ jsx("svg"`))
			Expect(result).NotTo(ContainCode(`import AtIcon from "/lib/svg/at.svg";`))
		})

		When("bundling", func() {
			It("bundles", func() {
				result := Build("lib/svg/relative.jsx", BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
				Expect(result).NotTo(ContainCode(`import AtIcon from "/lib/svg/at.svg";`))
			})
		})
	})

	When("importing bare svg specifier from jsx", func() {
		It("bundles", func() {
			result := Build("lib/svg/bare.jsx")

			Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
			Expect(result).To(ContainCode(`svg = /* @__PURE__ */ jsx("svg"`))
		})

		When("bundling", func() {
			It("bundles", func() {
				result := Build("lib/svg/bare.jsx", BuildOpts{Bundle: true})

				Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
				Expect(result).To(ContainCode(`var svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
			})
		})
	})

	When("importing svg from css", func() {
		It("should not bundle", func() {
			Expect(Build("lib/svg.css")).To(ContainCode(`url(/hue/icons/angle-right-regular.svg)`))
		})

		When("bundling", func() {
			It("should not bundle", func() {
				Expect(Build("lib/svg.css", BuildOpts{Bundle: true})).To(ContainCode(`
					url(/hue/icons/angle-right-regular.svg)`,
				))
			})
		})
	})

	When("importing remote svg from jsx", func() {
		When("bundling", func() {
			It("should bundle", func() {
				MockURL("/at.svg", svgContent)

				result := Build("lib/svg/remote.jsx", BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`
					var svg = /* @__PURE__ */ jsx("svg", { "aria-hidden": "true", focusable: "false", role: "img", xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 512 512", children: /* @__PURE__ */ jsx("path", { fill: "currentColor", d: "M504" }) });
				`))
			})
		})
	})

	When("importing remote svg from css", func() {
		When("bundling", func() {
			PIt("should not bundle or encode; leave as is", func() {
				var re = regexp.MustCompile(`^https?://.+(^\.svg)`)
				Expect(re.MatchString("https://sdfsdf.jsvg")).To(BeTrue())
			})

			PIt("should not bundle or encode; leave as is", func() {
				MockURL("/at.svg", svgContent)

				result := Build("lib/svg/remote.css", BuildOpts{Bundle: true})

				Expect(result).To(ContainCode(`background-image: url(https://proscenium.test/at.svg);`))
			})
		})
	})
})
