package proscenium_test

import (
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(parseCss)", func() {
	Describe("ParseCss", func() {
		It("should pass through regular css", func() {
			Expect("body{}").To(BeParsedTo("body{}", "/foo.css"))
		})

		Describe("mixins", func() {
			Describe("local", func() {
				It("undefined mixin is passed through", func() {
					Expect(`
						header {
							@mixin foo;
						}
					`).To(BeParsedTo(`
						header {
							@mixin foo;
						}
					`, "/foo.css"))
				})

				It("mixin not defined at root level is passed through", func() {
					Expect(`
						header {
							@define-mixin large-button {
								color: red;
							}
							div {
								@mixin foo;
							}
						}
					`).To(BeParsedTo(`
						header {
							@define-mixin large-button {
								color: red;
							}
							div {
								@mixin foo;
							}
						}
					`, "/foo.css"))
				})

				It("mixin is replaced with defined mixin", func() {
					Expect(`
						@define-mixin large-button {
							font-size: 20px;
							div { color: pink; }
						}
						header {
							@mixin large-button;
							color: blue;
						}
					`).To(BeParsedTo(`
						header {
							font-size: 20px;
							div { color: pink; }
							color: blue;
						}
					`, "/foo.css"))
				})

				It("dependencies are fully parsed", func() {
					Expect(`
						@define-mixin button {
							appearance: none;
						}
						@define-mixin large-button {
							@mixin button;
							font-size: 20px;
						}
						header {
							@mixin large-button;
						}
					`).To(BeParsedTo(`
						header {
							appearance: none;
							font-size: 20px;
						}
					`, "/foo.css"))
				})
			})

			Describe("from url()", func() {
				EntryPoint("lib/importing/mixins.css", func() {
					Describe("from absolute url", func() {
						AssertCode(`.mixin1 { content: "/lib/css_all/mixin1.css"; font-size: 10px; }`)
						AssertCode(`.mixin1 { content: "/lib/css_all/mixin1.css"; font-size: 10px; }`, Unbundle)
					})

					Describe("from relative url", func() {
						AssertCode(`.mixin2 { content: "/lib/css_all/mixin2.css"; font-size: 20px; }`)
						AssertCode(`.mixin2 { content: "/lib/css_all/mixin2.css"; font-size: 20px; }`, Unbundle)
					})

					Describe("from package", func() {
						AssertCode(`.mixin3 { content: "pkg/mixin.css"; font-size: 30px; }`)
						AssertCode(`.mixin3 { content: "pkg/mixin.css"; font-size: 30px; }`, Unbundle)
					})

					Describe("from file: package", func() {
						AssertCode(`.mixin4 { content: "pnpm-file/mixin.css"; font-size: 40px; }`)
						AssertCode(`.mixin4 { content: "pnpm-file/mixin.css"; font-size: 40px; }`, Unbundle)
					})

					Describe("from external file: package", func() {
						AssertCode(`.mixin-pnpm-file-ext { content: "pnpm-file-ext/mixin.css"; font-size: 45px; }`)
						AssertCode(`.mixin-pnpm-file-ext { content: "pnpm-file-ext/mixin.css"; font-size: 45px; }`, Unbundle)
					})

					Describe("from link: package", func() {
						AssertCode(`.mixin5 { content: "pnpm-link/mixin.css"; font-size: 50px; }`)
						AssertCode(`.mixin5 { content: "pnpm-link/mixin.css"; font-size: 50px; }`, Unbundle)
					})

					Describe("from external link: package", func() {
						AssertCode(`.mixin-pnpm-link-ext { content: "pnpm-link-ext/mixin.css"; font-size: 55px; }`)
						AssertCode(`.mixin-pnpm-link-ext { content: "pnpm-link-ext/mixin.css"; font-size: 55px; }`, Unbundle)
					})

					Describe("from internal @rubygems/*", func() {
						BeforeEach(func() {
							addGem("gem1", "dummy/vendor")
						})

						AssertCode(`.mixin6 { content: "@rubygems/gem1/mixin.css"; font-size: 60px; }`)
						AssertCode(`.mixin6 { content: "@rubygems/gem1/mixin.css"; font-size: 60px; }`, Unbundle)
					})

					Describe("from external @rubygems/*", func() {
						BeforeEach(func() {
							addGem("gem2", "external")
						})

						AssertCode(`.mixin7 { content: "@rubygems/gem2/mixin.css"; font-size: 70px; }`)
						AssertCode(`.mixin7 { content: "@rubygems/gem2/mixin.css"; font-size: 70px; }`, Unbundle)
					})

					Describe("from npm @rubygems/*", func() {
						BeforeEach(func() {
							addGem("gem_npm", "dummy/vendor")
						})

						AssertCode(`.mixin-gem_npm { content: "@rubygems/gem_npm/mixin.css"; font-size: 56px; }`)
						AssertCode(`.mixin-gem_npm { content: "@rubygems/gem_npm/mixin.css"; font-size: 56px; }`, Unbundle)

						Describe("without extension", func() {
							AssertCode(`.mixin-gem_npm_wo_ext { content: "@rubygems/gem_npm/mixin.css"; font-size: 57px; }`)
							AssertCode(`.mixin-gem_npm_wo_ext { content: "@rubygems/gem_npm/mixin.css"; font-size: 57px; }`, Bundle)
						})
					})

					PIt("nested relative mixin is resolved", func() {})
				})

				It("should cache mixin definition", func() {
					Expect(`
						header {
							@mixin red from url('/lib/mixins/colors.css');
						}
						footer {
							@mixin bigRed from url('/lib/mixins/colors.css');
						}
					`).To(BeParsedTo(`
						header {
							color: red;
						}
						footer {
							color: red;
							font-size: 50px;
						}
					`, "/foo.css"))
				})

				When("mixin file is not found", func() {
					// It("should log warning", Pending)

					It("should pass through the @mixin declaration", func() {
						Expect(`
						header {
							@mixin red from url("/unknown.css");
						}
					`).To(BeParsedTo(`
						header {
							@mixin red from url("/unknown.css");
						}
					`, "/foo.css"))
					})
				})

				When("mixin is undefined", func() {
					It("mixin is passed through", func() {
						Expect(`
						header {
							@mixin unknown from url("/lib/mixins/colors.css");
						}
					`).To(BeParsedTo(`
						header {
							@mixin unknown from url("/lib/mixins/colors.css");
						}
					`, "/foo.css"))
					})
				})

				When("mixin declaration has no name", func() {
					It("mixin is passed through", func() {
						Expect(`
							header {
								@mixin purple from url("/lib/mixins/colors.css");
							}
						`).To(BeParsedTo(`
							header {
								@mixin purple from url("/lib/mixins/colors.css");
							}
						`, "/foo.css"))
					})
				})

				When("mixin declaration is nested", func() {
					It("should pass through nested mixin", func() {
						Expect(`
							header {
								@mixin blue from url("/lib/mixins/colors.css");
							}
						`).To(BeParsedTo(`
							header {
								color: blue;
								@define-mixin pink {
									color: pink;
								}
							}
						`, "/foo.css"))
					})
				})

				It("should include nested mixins", func() {
					Expect(`
						header {
							@mixin bigRed from url("/lib/mixins/colors.css");
						}
					`).To(BeParsedTo(`
						header {
							color: red;
							font-size: 50px;
						}
					`, "/foo.css"))
				})
			})
		})

		Describe("css modules", func() {
			It("path is not a css module", func() {
				Expect(`
					.title { color: green; }
				`).To(BeParsedTo(`
					.title { color: green; }
				`, "/foo.css"))
			})

			It("should support mixins", func() {
				Expect(`
					@define-mixin red {
						color: red;
					}
					.title { @mixin red; }
				`).To(BeParsedTo(`
					.title-43c30152 { color: red; }
				`, "/foo.module.css"))
			})

			It("should rename classes", func() {
				Expect(`
					.title { color: green; }
				`).To(BeParsedTo(`
					.title-43c30152 { color: green; }
				`, "/foo.module.css"))
			})

			It("should rename nested classes", func() {
				Expect(`
					.title {
						color: green;
						.subtitle { color: blue; }
					}
				`).To(BeParsedTo(`
					.title-43c30152 {
						color: green;
						.subtitle-43c30152 { color: blue; }
					}
				`, "/foo.module.css"))
			})

			It("should rename compound classes", func() {
				Expect(`
					.title.subtitle { color: green; }
				`).To(BeParsedTo(`
					.title-43c30152.subtitle-43c30152 { color: green; }
				`, "/foo.module.css"))
			})

			Describe("local function", func() {
				It("top level local", func() {
					Expect(`
						.title { color: red; }
						:local(.subtitle) { color: green; }
					`).To(BeParsedTo(`
						.title-43c30152 { color: red; }
						.subtitle-43c30152 { color: green; }
					`, "/foo.module.css"))
				})

				It("should rename argument", func() {
					Expect(`
						:global {
							:local(.subtitle) { color: green; }
							.title { color: red; }
						}
					`).To(BeParsedTo(`
						.subtitle-43c30152 { color: green; }
						.title { color: red; }
					`, "/foo.module.css"))
				})

				It("nested locals are parsed", func() {
					Expect(`
						:global(.subtitle) {
							:local(.day) { color: orange; }
							:local .month { color: red; }
							:local {
								.year { color: pink; }
								:global(.foo) { color: blue; }
							}
						}
					`).To(BeParsedTo(`
						.subtitle {
							.day-43c30152 { color: orange; }
							.month-43c30152 { color: red; }
							.year-43c30152 { color: pink; }
							.foo { color: blue; }
						}
					`, "/foo.module.css"))
				})
			})

			Describe("local shorthand with argument", func() {
				It("should not rename argument", func() {
					Expect(`
						:global {
							:local
								.subtitle { color: green; }
						}
					`).To(BeParsedTo(`
						.subtitle-43c30152 { color: green; }
					`, "/foo.module.css"))
				})
			})

			Describe("global function", func() {
				It("should not rename argument", func() {
					Expect(`
						.title { color: blue; }
						:global(.subtitle) { color: green; }
						.author { color: red; }
					`).To(BeParsedTo(`
						.title-43c30152 { color: blue; }
						.subtitle { color: green; }
						.author-43c30152 {	color: red; }
					`, "/foo.module.css"))
				})

				It("nested globals are parsed", func() {
					Expect(`
						:global(.subtitle) {
							:global(.day) { color: orange; }
							:global .month { color: red; }
							:global {
								.year { color: pink; }
							}
						}
					`).To(BeParsedTo(`
						.subtitle {
							.day { color: orange; }
							.month { color: red; }
							.year { color: pink; }
						}
					`, "/foo.module.css"))
				})

				It("nested classes should be renamed", func() {
					Expect(`
						:global(.subtitle) {
							color: green;
							.foo { color: orange; }
						}
					`).To(BeParsedTo(`
						.subtitle {
							color: green;
							.foo-43c30152 { color: orange; }
						}
					`, "/foo.module.css"))
				})
			})

			Describe("global shorthand with argument", func() {
				It("should not rename argument", func() {
					Expect(`
						.title { color: blue; }
						:global
							.subtitle { color: green; }
						.author { color: red; }
					`).To(BeParsedTo(`
						.title-43c30152 { color: blue; }
						.subtitle { color: green; }
						.author-43c30152 { color: red; }
					`, "/foo.module.css"))
				})

				It("nested globals are ignored", func() {
					Expect(`
						.title { color: blue; }
						:global .subtitle {
							color: green;
							:global(.day) { color: orange; }
							:global .month { color: pink; }
							:global {
								.year { color: black; }
							}
						}
						.author { color: red; }
					`).To(BeParsedTo(`
						.title-43c30152 { color: blue; }
						.subtitle {
							color: green;
							.day { color: orange; }
							.month { color: pink; }
							.year { color: black; }
						}
						.author-43c30152 {	color: red; }
					`, "/foo.module.css"))
				})

				It("nested classes should be renamed", func() {
					Expect(`
						:global .subtitle {
							color: green;
							.foo { color: orange; }
						}
					`).To(BeParsedTo(`
						.subtitle {
        			color: green;
        			.foo-43c30152 { color: orange; }
						}
					`, "/foo.module.css"))
				})
			})

			Describe("global shorthand without argument", func() {
				It("should rename all children", func() {
					Expect(`
						:global {
							.subtitle {
								color: green;
								.foo { color: orange; }
							}
							.bar { color: blue; }
						}
						.author { color: red; }
					`).To(BeParsedTo(`
						.subtitle {
							color: green;
							.foo { color: orange; }
						}
						.bar { color: blue; }
						.author-43c30152 { color: red; }
					`, "/foo.module.css"))
				})

				It("nested globals without class ident are ignored", func() {
					Expect(`
						:global {
							:global {
								.subtitle { color: green; }
							}
						}
					`).To(BeParsedTo(`
						.subtitle { color: green; }
					`, "/foo.module.css"))
				})

				It("nested globals with class ident are ignored", func() {
					Expect(`
						:global {
							.title { color: green; }
							:global(.subtitle) {
								color: blue;
								:global {
									.day { color: orange; }
								}
							}
						}
					`).To(BeParsedTo(`
						.title { color: green; }
						.subtitle {
							color: blue;
							.day { color: orange; }
						}
					`, "/foo.module.css"))
				})
			})
		})
	})
})
