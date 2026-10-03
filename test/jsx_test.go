package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// JSX compiles with esbuild's automatic runtime, React by default. The README documents choosing
// another library with jsxImportSource, which esbuild reads from the nearest tsconfig.json or
// jsconfig.json, or from a comment in the file.
var _ = Describe("b.BuildToString(jsx)", func() {
	It("uses React's runtime by default", func() {
		_, code, _ := b.BuildToString("lib/jsx_default.jsx", testConfig)

		Expect(code).To(ContainSubstring("node_modules/react/jsx-runtime.js"))
	})

	It("uses the jsxImportSource of the nearest tsconfig.json", func() {
		_, code, _ := b.BuildToString("lib/jsx_import_source/component.jsx", testConfig)

		Expect(code).To(ContainSubstring(`from "preact/jsx-runtime"`))
		Expect(code).NotTo(ContainSubstring("node_modules/react/"))
	})

	It("uses a @jsxImportSource comment in the file", func() {
		_, code, _ := b.BuildToString("lib/jsx_pragma.jsx", testConfig)

		Expect(code).To(ContainSubstring(`from "preact/jsx-runtime"`))
		Expect(code).NotTo(ContainSubstring("node_modules/react/"))
	})
})
