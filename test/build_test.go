package proscenium_test

import (
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build", func() {
	It("should fail on unknown entrypoint", func() {
		result := Build("unknown.js")

		Expect(result.Errors[0].Text).To(Equal("Could not resolve \"unknown.js\""))
	})

	It("should build js", func() {
		Expect(Build("lib/foo.js")).To(ContainCode(`console.log("/lib/foo.js")`))
	})

	It("should bundle rjs", Pending, func() {
		MockURL("/constants.rjs", "export default 'constants';")

		Expect(Build("lib/rjs.js")).To(ContainCode(`"constants"`))
	})

	It("should build jsx", func() {
		result := Build("lib/component.jsx")

		Expect(result).NotTo(ContainCode(`
			import { jsx } from "/node_modules/.pnpm/react@18.2.0/node_modules/react/jsx-runtime.js";
		`))

		Expect(Build("lib/component.jsx")).To(ContainCode(`
			var import_jsx_runtime = __toESM(require_jsx_runtime());
			var Component = /* @__PURE__ */ __name(() => {
				return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { children: "Hello" });
			}, "Component");
			var component_default = Component;
			export {
				component_default as default
			};
		`))
	})

	It("should bundle bare module", func() {
		Expect(Build("lib/import_npm_module.js")).NotTo(ContainCode(`
			import { isIP } from "/node_modules/.pnpm/is-ip@
		`))
	})

	It("should resolve extension-less imports", func() {
		Expect(Build("lib/import_absolute_module_without_extension.js")).To(ContainCode(`
			console.log("/lib/foo.js")
		`))
	})

	It("should bundle relative path", func() {
		Expect(Build("lib/import_relative_module.js")).To(ContainCode(`
			console.log("/lib/foo4.js")
		`))
	})

	It("should bundle absolute path", func() {
		Expect(Build("lib/import_absolute_module.js")).To(ContainCode(`
			console.log("/lib/foo4.js")
		`))
	})

	It("tree shakes bare import", func() {
		Expect(Build("lib/import_tree_shake.js")).To(EqualCode(`
			var __defProp = Object.defineProperty;
			var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

			// packages/mypackage/treeshake.js
			function one() {
				console.log("one");
			}
			__name(one, "one");

			// node_modules/.pnpm/lodash-es@4.17.21/node_modules/lodash-es/noop.js
			function noop() {
			}
			__name(noop, "noop");
			var noop_default = noop;

			// lib/import_tree_shake.js
			noop_default();
			one();
		`))
	})

	It("does not bundle URLs", func() {
		MockURL("/import-url-module.js", "export default 'Hello World'")

		Expect(Build("lib/import_url.js")).To(ContainCode(`
			import myFunction from "/https%3A%2F%2Fproscenium.test%2Fimport-url-module.js";
		`))
	})

	It("should define NODE_ENV", func() {
		result := Build("lib/define_node_env.js")

		Expect(result).To(ContainCode(`console.log("test")`))
	})

	When("css", func() {
		It("should bundle absolute path", func() {
			Expect(Build("lib/import_absolute.css")).To(ContainCode(`
				.stuff {
					color: red;
				}
			`))
		})

		It("should bundle relative path", func() {
			result := Build("lib/import_relative.css")

			Expect(result).To(ContainCode(`
				.body {
					color: red;
				}
			`))
			Expect(result).To(ContainCode(`
				.body {
					color: blue;
				}
			`))
		})

		It("should not bundle fonts", func() {
			result := Build("lib/fonts.css")

			Expect(result).To(ContainCode(`url(/somefont.woff2)`))
			Expect(result).To(ContainCode(`url(/somefont.woff)`))
		})
	})
})
