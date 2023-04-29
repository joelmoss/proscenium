package builder_test

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	. "joelmoss/proscenium/internal/test"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"

	"github.com/evanw/esbuild/pkg/api"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/svg", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		builder.DiskvCache.EraseAll()
	})

	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	build := func(path string, rest ...bool) api.BuildResult {
		bundle := false
		if len(rest) > 0 {
			bundle = rest[0]
		}

		return builder.Build(builder.BuildOptions{
			Path:   path,
			Root:   root,
			Bundle: bundle,
		})
	}

	When("importing local svg in jsx", func() {
		It("bundles", func() {
			result := build("lib/svg/local.jsx")

			Expect(result).To(ContainCode(`svg = /* @__PURE__ */ jsx("svg"`))
			Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
		})

		When("bundling", func() {
			It("bundles", func() {
				result := build("lib/svg/local.jsx", true)

				Expect(result).To(ContainCode(`svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
				Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
			})
		})
	})

	When("importing bare svg specifier in jsx", func() {
		It("bundles", func() {
			result := build("lib/svg/bare.jsx")

			Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
			Expect(result).To(ContainCode(`svg = /* @__PURE__ */ jsx("svg"`))
		})

		When("bundling", func() {
			It("bundles", func() {
				result := build("lib/svg/bare.jsx", true)

				Expect(result).NotTo(ContainCode(`import AtIcon from "/public/at.svg";`))
				Expect(result).To(ContainCode(`var svg = /* @__PURE__ */ (0, import_jsx_runtime.jsx)("svg"`))
			})
		})
	})

	When("importing svg in css", func() {
		It("should not bundle", func() {
			Expect(build("lib/svg.css")).To(ContainCode(`url(/hue/icons/angle-right-regular.svg)`))
		})

		When("bundling", func() {
			It("should not bundle", func() {
				Expect(build("lib/svg.css", true)).To(ContainCode(`url(/hue/icons/angle-right-regular.svg)`))
			})
		})
	})

	PIt("url('/hue/icons/angle-right-regular.svg')")

	PIt("imports remote svg specifier in jsx", func() {
		MockURL("/at.svg", `
			<svg aria-hidden="true" focusable="false" data-prefix="far" data-icon="at" class="svg-inline--fa fa-at fa-w-16" role="img" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path fill="currentColor" d="M504 232C504 95.751 394.053 8 256 8 118.94 8 8 118.919 8 256c0 137.059 110.919 248 248 248 52.926 0 104.681-17.079 147.096-48.321 5.501-4.052 6.423-11.924 2.095-17.211l-15.224-18.597c-4.055-4.954-11.249-5.803-16.428-2.041C339.547 442.517 298.238 456 256 456c-110.28 0-200-89.72-200-200S145.72 56 256 56c109.469 0 200 65.02 200 176 0 63.106-42.478 98.29-83.02 98.29-19.505 0-20.133-12.62-16.366-31.463l28.621-148.557c1.426-7.402-4.245-14.27-11.783-14.27h-39.175a12.005 12.005 0 0 0-11.784 9.735c-1.102 5.723-1.661 8.336-2.28 13.993-11.923-19.548-35.878-31.068-65.202-31.068C183.412 128.66 120 191.149 120 281.53c0 61.159 32.877 102.11 93.18 102.11 29.803 0 61.344-16.833 79.749-42.239 4.145 30.846 28.497 38.01 59.372 38.01C451.467 379.41 504 315.786 504 232zm-273.9 97.35c-28.472 0-45.47-19.458-45.47-52.05 0-57.514 39.56-93.41 74.61-93.41 30.12 0 45.471 21.532 45.471 51.58 0 46.864-33.177 93.88-74.611 93.88z"></path></svg>
		`)

		Expect(build("lib/svg/remote.jsx")).To(ContainCode(`
			var RAILS_ENV_default = "test";
		`))
	})
})
