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
		AssertCode(`return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`)
	})

	EntryPoint("lib/svg/absolute_tsx.tsx", func() {
		AssertCode(`return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`)
	})

	EntryPoint("lib/svg/relative.jsx", func() {
		AssertCode(`return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`)
	})

	EntryPoint("lib/svg/bare.jsx", func() {
		AssertCode(`return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`)
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

			Expect(code).To(ContainCode(`return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
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

			Expect(code).To(ContainCode(`return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
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
			return /* @__PURE__ */ jsx("svg", { "aria-hidden": "true", focusable: "false", role: "img", xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 512 512", children: /* @__PURE__ */ jsx("path", { fill: "currentColor", d: "M504" }) });
		`))
	})

	// A remote SVG is markup, not code. It used to be spliced into the module as JSX, so an
	// expression in it was compiled with the app's env var defines, and anything after its closing
	// tag ran in the bundle.
	It("does not replace env vars in remote svg from jsx", func() {
		testConfig.EnvVars = map[string]string{"API_KEY": "secret-value"}
		MockURL("/at.svg", `<svg><text>{proscenium.env.API_KEY}</text><image href="{proscenium.env.API_KEY}" /></svg>`)

		success, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

		Expect(success).To(BeTrue())
		Expect(code).NotTo(ContainSubstring("secret-value"))
		Expect(code).To(ContainCode(`jsx("text", { children: "{proscenium.env.API_KEY}" })`))
		Expect(code).To(ContainCode(`jsx("image", { href: "{proscenium.env.API_KEY}" })`))
	})

	It("does not run code after the root element of remote svg from jsx", func() {
		MockURL("/at.svg", `<svg></svg>; globalThis.injected = 1; const z = <svg></svg>`)

		success, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

		Expect(success).To(BeTrue())
		Expect(code).NotTo(ContainSubstring("injected"))
	})

	// Names are written into the JSX unquoted, so anything that is not a plain name fails the build
	// rather than being emitted. An uppercase element would be read as a variable in scope.
	DescribeTable("fails the build for remote svg from jsx that is not well formed",
		func(svg string, message string) {
			MockURL("/at.svg", svg)

			success, result, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

			Expect(success).To(BeFalse())
			plugin, text := firstBuildError(result)
			Expect(plugin).To(Equal("svg"))
			Expect(text).To(Equal("cannot read https://proscenium.test/at.svg as SVG: " + message))
		},
		Entry("an uppercase element name", `<svg><Children /></svg>`, `invalid element name "Children"`),
		Entry("an attribute name JSX cannot take", `<svg a.b="1"></svg>`, `invalid attribute name "a.b"`),
		Entry("a mismatched closing tag", `<svg><g></svg>`, `unexpected closing tag "svg"`),
		Entry("an unclosed element", `<svg><g></g>`, `unclosed element "svg"`),
		Entry("no element at all", `just text`, `no root element`),
	)

	// Whitespace-only text between elements is dropped, as JSX dropped it, so a pretty-printed svg
	// gains no text children from its indentation.
	It("reads pretty-printed svg with a doctype and entities", func() {
		MockURL("/at.svg", "<?xml version=\"1.0\"?>\n<!DOCTYPE svg>\n<svg>\n  <g>\n    <text>a &amp; b&nbsp;c</text>\n  </g>\n</svg>\n")

		success, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

		Expect(success).To(BeTrue())
		Expect(code).To(ContainCode(`return /* @__PURE__ */ jsx("svg", { children: /* @__PURE__ */ jsx("g", { children: /* @__PURE__ */ jsx("text", { children: "a & b\xA0c" }) }) });`))
	})

	// The component is the SVG's own JSX, with no import and nothing from a particular JSX library,
	// so whatever JSX runtime compiles it renders it.
	It("renders remote svg from jsx with no import of its own", func() {
		MockURL("/at.svg", `<svg><path d="1" /></svg>`)

		success, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

		// React is bundled here as the default JSX runtime, so its own source is in the output;
		// only the old wrapper ever called Children.only or read svg.props.
		Expect(success).To(BeTrue())
		Expect(code).NotTo(ContainSubstring("Children.only("))
		Expect(code).NotTo(ContainSubstring("svg.props"))
		Expect(code).To(ContainCode(`return /* @__PURE__ */ jsx("svg", { children: /* @__PURE__ */ jsx("path", { d: "1" }) });`))
	})

	It("renders the root class as className, and leaves a descendant's class alone", func() {
		MockURL("/at.svg", `<svg class="a"><g class="b"></g></svg>`)

		success, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

		Expect(success).To(BeTrue())
		Expect(code).To(ContainCode(`jsx("svg", { className: "a", children: /* @__PURE__ */ jsx("g", { class: "b" }) })`))
	})

	// The old wrapper passed the children through Children.only, which throws for more than one.
	It("renders every child of remote svg from jsx", func() {
		MockURL("/at.svg", `<svg><path d="1" /><path d="2" /></svg>`)

		success, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

		Expect(success).To(BeTrue())
		Expect(code).To(ContainCode(`return /* @__PURE__ */ jsxs("svg", { children: [ /* @__PURE__ */ jsx("path", { d: "1" }), /* @__PURE__ */ jsx("path", { d: "2" }) ] });`))
	})

	It("keeps namespaced attributes, and skips the xml declaration and comments", func() {
		MockURL("/at.svg", `<?xml version="1.0"?><!-- c --><svg xmlns:xlink="http://www.w3.org/1999/xlink"><use xlink:href="#a" /></svg>`)

		success, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

		Expect(success).To(BeTrue())
		Expect(code).To(ContainCode(`jsx("use", { "xlink:href": "#a" })`))
	})

	// Text follows JSX's whitespace rule, as it did while SVG was spliced in as JSX.
	DescribeTable("reads text in remote svg from jsx as JSX would",
		func(svg string, expected string) {
			MockURL("/at.svg", svg)

			success, code, _ := b.BuildToString("lib/svg/remote.jsx", testConfig)

			Expect(success).To(BeTrue())
			Expect(code).To(ContainCode(expected))
		},
		Entry("keeps a space between elements on one line",
			`<svg><text><tspan>a</tspan> <tspan>b</tspan></text></svg>`,
			`jsxs("text", { children: [ /* @__PURE__ */ jsx("tspan", { children: "a" }), " ", /* @__PURE__ */ jsx("tspan", { children: "b" }) ] })`),
		Entry("collapses a line break and its indentation to one space",
			"<svg><title>\n  a\n  b\n</title></svg>",
			`jsx("title", { children: "a b" })`),
		Entry("keeps an entity space at the edge of a line",
			"<svg><text>a&nbsp;\n</text></svg>",
			`jsx("text", { children: "a\xA0" })`),
		Entry("joins text and CDATA into one child",
			`<svg><style>a{}<![CDATA[b{}]]></style></svg>`,
			`jsx("style", { children: "a{}b{}" })`),
		Entry("allows an uppercase namespace prefix, which JSX reads as a string",
			`<svg><RDF:RDF /></svg>`,
			`jsx("RDF:RDF", {})`),
	)

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
