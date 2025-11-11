package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("BuildToString(css)", func() {
	EntryPoint("lib/importing/application.css", func() {
		Describe("import absolute path", func() {
			AssertCode(`.app_one { content: "/lib/importing/app/one.css"; }`)
			AssertCode(`@import "/lib/importing/app/one.css";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`.app_two { content: "/lib/importing/app/two.css"; }`)
				AssertCode(`@import "/lib/importing/app/two.css";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`.app_index { content: "/lib/importing/app/index.css"; }`)
				AssertCode(`@import "/lib/importing/app/index.css";`, Unbundle)
			})
		})

		Describe("import relative path", func() {
			AssertCode(`.app_three { content: "/lib/importing/app/three.css"; }`)
			AssertCode(`@import "/lib/importing/app/three.css";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`.app_four { content: "/lib/importing/app/four.css"; }`)
				AssertCode(`@import "/lib/importing/app/four.css";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`.app_five_index { content: "/lib/importing/app/five/index.css"; }`)
				AssertCode(`@import "/lib/importing/app/five/index.css";`, Unbundle)
			})
		})

		Describe("URL", func() {
			AssertCode(`@import "https://proscenium.test/foo.css";`)
			AssertCode(`@import "https://proscenium.test/foo.css";`, Unbundle)
		})
	})

	EntryPoint("lib/importing/package.css", func() {
		Describe("import absolute path", func() {
			AssertCode(`.pkg_one { content: "pkg/one.css"; }`)
			AssertCode(`@import "/node_modules/pkg/one.css";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`.pkg_two { content: "pkg/two.css"; }`)
				AssertCode(`@import "/node_modules/pkg/two.css";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`.pkg_index { content: "pkg/index.css"; }`)
				AssertCode(`@import "/node_modules/pkg/index.css";`, Unbundle)
			})
		})

		Describe("import pkg dependency", func() {
			AssertCode(`.pkg_dep_index { content: "pkg_dep/index.css"; }`)
		})

		Describe("import app dependency", func() {
			AssertCode(`.pnpm_file_one { content: "pnpm-file/one.css"; }`)
			AssertCode(`.pnpm_file_ext_one { content: "pnpm-file-ext/one.css"; }`)
			AssertCode(`.pnpm_link_one { content: "pnpm-link/one.css"; }`)
			AssertCode(`.pnpm_link_ext_one { content: "pnpm-link-ext/one.css"; }`)
		})

		Describe("import app path", func() {
			AssertCode(`.app_one { content: "/lib/importing/app/one.css"; }`)
		})
	})

	EntryPoint("lib/importing/pnpm_link.css", func() {
		Describe("import absolute path", func() {
			AssertCode(`.pnpm_link_one { content: "pnpm-link/one.css"; }`)
			AssertCode(`@import "/node_modules/pnpm-link/one.css";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`.pnpm_link_two { content: "pnpm-link/two.css"; }`)
				AssertCode(`@import "/node_modules/pnpm-link/two.css";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`.pnpm_link_three_index { content: "pnpm-link/three/index.css"; }`)
				AssertCode(`@import "/node_modules/pnpm-link/three/index.css";`, Unbundle)
			})
		})
	})

	EntryPoint("lib/importing/pnpm_link_external.css", func() {
		Describe("import absolute path", func() {
			AssertCode(`.pnpm_link_ext_one { content: "pnpm-link-ext/one.css"; }`)
			AssertCode(`@import "/node_modules/pnpm-link-ext/one.css";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`.pnpm_link_ext_two { content: "pnpm-link-ext/two.css"; }`)
				AssertCode(`@import "/node_modules/pnpm-link-ext/two.css";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`.pnpm_link_ext_three_index { content: "pnpm-link-ext/three/index.css"; }`)
				AssertCode(`@import "/node_modules/pnpm-link-ext/three/index.css";`, Unbundle)
			})
		})
	})

	EntryPoint("lib/importing/pnpm_file.css", func() {
		Describe("import absolute path", func() {
			AssertCode(`.pnpm_file_one { content: "pnpm-file/one.css"; }`)
			AssertCode(`@import "/node_modules/pnpm-file/one.css";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`.pnpm_file_two { content: "pnpm-file/two.css"; }`)
				AssertCode(`@import "/node_modules/pnpm-file/two.css";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`.pnpm_file_three_index { content: "pnpm-file/three/index.css"; }`)
				AssertCode(`@import "/node_modules/pnpm-file/three/index.css";`, Unbundle)
			})
		})

		Describe("import pkg dependency", func() {
			AssertCode(`.pkg_dep_index { content: "pkg_dep/index.css"; }`)
			AssertCode(`@import "/node_modules/pnpm-file/dependency.css";`, Unbundle)
		})
	})

	EntryPoint("lib/importing/pnpm_file_external.css", func() {
		Describe("import absolute path", func() {
			AssertCode(`.pnpm_file_ext_one { content: "pnpm-file-ext/one.css"; }`)
			AssertCode(`@import "/node_modules/pnpm-file-ext/one.css";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`.pnpm_file_ext_two { content: "pnpm-file-ext/two.css"; }`)
				AssertCode(`@import "/node_modules/pnpm-file-ext/two.css";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`.pnpm_file_ext_three_index { content: "pnpm-file-ext/three/index.css"; }`)
				AssertCode(`@import "/node_modules/pnpm-file-ext/three/index.css";`, Unbundle)
			})
		})

		Describe("import pkg dependency", func() {
			AssertCode(`.pkg_dep_index { content: "pkg_dep/index.css"; }`)
			AssertCode(`@import "/node_modules/pnpm-file-ext/dependency.css";`, Unbundle)
		})
	})

	EntryPoint("lib/importing/css_module.css", func() {
		AssertCode(`.app_one_module_0b3293c7{content:"/lib/importing/app/one.module.css"}`, Production)
		AssertCode(`@import "/lib/importing/app/one.module.css";`, Unbundle)
		AssertCode(`
			.app_one_module_0b3293c7_lib-importing-app-one-module {
				content: "/lib/importing/app/one.module.css";
			}`,
		)

		Describe("nested", func() {
			AssertCode(`.app_two_module_de28557c{content:"/lib/importing/app/two.module.css"}`, Production)
			AssertCode(`.app_two_module_de28557c_lib-importing-app-two-module { content: "/lib/importing/app/two.module.css"; }`)
		})

		Describe("from package", func() {
			AssertCode(`.pkg_one_module_1742dae2{content:"pkg/one.module.css"}`, Production)
			AssertCode(`@import "/node_modules/pkg/one.module.css";`, Unbundle)
			AssertCode(`
				.pkg_one_module_1742dae2_node_modules--pnpm-pkg_git_https___git_gist-github-com_c3d9087f5f214e1f0d9719e4a7d38474-git_2a499df3143c5637ebaa3be5c4b983ebc094aeff-node_modules-pkg-one-module {
					content: "pkg/one.module.css";
				}`,
			)
		})
	})

	EntryPoint("lib/importing/fonts.css", func() {
		AssertCode(`url(/somefont.woff2)`)
		AssertCode(`url(/somefont.woff)`)
	})

	Context("from @rubygems/*", func() {
		BeforeEach(func() {
			addGem("gem_npm", "dummy/vendor")
			addGem("gem_link", "dummy/vendor")
			addGem("gem_file", "dummy/vendor")
		})

		It("builds from npm install", func() {
			_, code, _ := b.BuildToString("node_modules/@rubygems/gem_npm/index.css")

			Expect(code).To(ContainCode(`.myClass {	color: pink; }`))
		})

		Context("css modules", func() {
			It("builds from npm install", func() {
				_, code, _ := b.BuildToString("node_modules/@rubygems/gem_npm/index.module.css")

				Expect(code).To(ContainCode(`.myClass_125b3fe9_vendor-gem_npm-index-module { color: pink; }`))
			})

			It("builds from file:* npm install", func() {
				_, code, _ := b.BuildToString("node_modules/@rubygems/gem_file/index.module.css")

				Expect(code).To(ContainCode(`.myClass_dbc84b0b_vendor-gem_file-index-module { color: pink; }`))
			})
		})

		Context("css module; dev names", func() {
			BeforeEach(func() {
				types.Config.UseDevCSSModuleNames = true
			})

			It("builds npm install", func() {
				addGem("gem_npm", "dummy/vendor")

				_, code, _ := b.BuildToString("node_modules/@rubygems/gem_npm/index.module.css")

				Expect(code).To(ContainCode(`
					.myClass_125b3fe9_vendor-gem_npm-index-module {
						color: pink;
					}
				`))
			})
		})
	})

	Describe("importing css module from js", func() {
		var expectedCode = `
			var d = document;
			var u = "/lib/styles.module.css";
			var es = d.querySelector("#_0d45f40a");
			var el = d.querySelector('link[href="' + u + '"]');
			if (!es && !el) {
				const e = d.createElement("style");
				e.id = "_0d45f40a";
				e.dataset.href = u;
				e.dataset.prosceniumStyle = true;
				e.appendChild(d.createTextNode(String.raw` + "`/* lib/styles.module.css */" + `
					.myClass_0d45f40a_lib-styles-module {
						color: pink;
					}` + "`" + `));
				const ps = d.head.querySelector("[data-proscenium-style]");
				ps ? d.head.insertBefore(e, ps) : d.head.appendChild(e);
			}
			var styles_default = new Proxy({}, {
				get(t, p, r) {
					return p in t || typeof p === "symbol" ? Reflect.get(t, p, r) : p + "_0d45f40a_lib-styles-module";
				}
			});
		`

		When("Bundle = true", func() {
			BeforeEach(func() {
				types.Config.Bundle = true
			})

			It("non css module", func() {
				_, result, _ := b.BuildToString("app/components/css_import.js")

				Expect(result).To(ContainCode(`var css_import_default = {};`))
			})

			It("includes stylesheet and proxies class names", func() {
				_, result, _ := b.BuildToString("lib/import_css_module.js")

				Expect(result).To(ContainCode(expectedCode))
			})

			It("import relative css module from js", func() {
				_, result, _ := b.BuildToString("lib/import_relative_css_module.js")

				Expect(result).To(ContainCode(expectedCode))
			})
		})

		When("Bundle = false", func() {
			BeforeEach(func() {
				types.Config.Bundle = false
			})

			It("import relative css module from js", func() {
				_, result, _ := b.BuildToString("lib/import_relative_css_module.js")

				Expect(result).To(ContainCode(`import styles from "/lib/styles.module.css";`))
			})

			It("includes stylesheet and proxies class names", func() {
				_, result, _ := b.BuildToString("lib/import_css_module.js")

				Expect(result).To(ContainCode(`import styles from "/lib/styles.module.css";`))
			})
		})

		When("importing css module from css module", func() {
			It("should bundle with different digest", func() {
				_, result, _ := b.BuildToString("lib/css_modules/import_css_module.js")

				Expect(result).To(ContainCode(`.foo_3977965b_lib-css_modules-basic-module { color: red; }`))
				Expect(result).To(ContainCode(`.bar_24efbaab_lib-css_modules-import_css_module-module { color: blue; }`))
			})
		})

		Context("internal @rubygems/*", func() {
			BeforeEach(func() {
				addGem("gem1", "dummy/vendor")
			})

			It("includes stylesheet and proxies class names", func() {
				_, result, _ := b.BuildToString("lib/rubygems/internal_import_css_module.js")

				Expect(result).To(ContainCode(`var u = "/node_modules/@rubygems/gem1/styles.module.css";`))
				Expect(result).To(ContainCode(`var es = d.querySelector("#_f8ab1250");`))
				Expect(result).To(ContainCode(`.myClass_f8ab1250_vendor-gem1-styles-module { color: pink; }`))
			})
		})

		Context("external @rubygems/*", func() {
			BeforeEach(func() {
				addGem("gem2", "external")
			})

			It("includes stylesheet and proxies class names", func() {
				_, result, _ := b.BuildToString("lib/rubygems/external_import_css_module.js")

				Expect(result).To(ContainCode(`var u = "/node_modules/@rubygems/gem2/styles.module.css";`))
				Expect(result).To(ContainCode(`var es = d.querySelector("#_b0eba875");`))
				Expect(result).To(ContainCode(`.myClass_b0eba875_---external-gem2-styles-module { color: pink; }`))
			})
		})
	})
})
