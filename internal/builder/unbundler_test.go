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

var _ = Describe("Internal/Builder.unbundler", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		plugin.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	It("should fail on unknown entrypoint", func() {
		result := Build("unknown.js")

		Expect(result.Errors[0].Text).To(Equal("Could not resolve \"unknown.js\""))
	})

	It("should build js", func() {
		Expect(Build("lib/foo.js")).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("should build jsx", func() {
		Expect(Build("lib/component.jsx")).To(EqualCode(`
			var __defProp = Object.defineProperty;
			var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

			// lib/component.jsx
			import { jsx } from "/node_modules/.pnpm/react@18.2.0/node_modules/react/jsx-runtime.js";
			var Component = /* @__PURE__ */ __name(() => {
				return /* @__PURE__ */ jsx("div", { children: "Hello" });
			}, "Component");
			var component_default = Component;
			export {
				component_default as default
			};
		`))
	})

	It("should import bare module", func() {
		Expect(Build("lib/import_npm_module.js")).To(ContainCode(`
			import { isIP } from "/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js"
		`))
	})

	It("should import relative path", func() {
		Expect(Build("lib/import_relative_module.js")).To(ContainCode(`
			import foo4 from "/lib/foo4.js"
		`))
	})

	It("should import absolute path", func() {
		Expect(Build("lib/import_absolute_module.js")).To(ContainCode(`
			import foo4 from "/lib/foo4.js"
		`))
	})

	It("should define NODE_ENV", func() {
		Expect(Build("lib/define_node_env.js")).To(ContainCode(`console.log("test")`))
	})
})
