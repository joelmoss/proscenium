package proscenium_test

import (
	"joelmoss/proscenium/internal/css"
	. "joelmoss/proscenium/test/support"
	"strings"

	"github.com/MakeNowJust/heredoc"
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

				It("undefined local mixin generates a warning", func() {
					input := strings.TrimSpace(heredoc.Doc(`
						header {
							@mixin foo;
						}
					`))
					_, warnings, err := css.ParseCss(input, "/foo.css")
					Expect(err).NotTo(HaveOccurred())
					Expect(warnings).To(HaveLen(1))
					Expect(warnings[0].Text).To(Equal(`Mixin "foo" not defined in "/foo.css"`))
					Expect(warnings[0].FilePath).To(Equal("/foo.css"))
					Expect(warnings[0].Line).To(Equal(2))
					Expect(warnings[0].Column).To(Equal(1))
					Expect(warnings[0].Length).To(Equal(len("@mixin foo")))
					Expect(warnings[0].LineText).To(Equal("\t@mixin foo;"))
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

						It("undefined @rubygems mixin generates a warning", func() {
							input := strings.TrimSpace(heredoc.Doc(`
								header {
									@mixin table from url("@rubygems/gem1/table.css");
									@mixin undefMixin from url("@rubygems/gem1/table.css");
								}
							`))
							_, warnings, err := css.ParseCss(input, "/foo.css")
							Expect(err).NotTo(HaveOccurred())
							Expect(warnings).To(HaveLen(1))
							Expect(warnings[0].Text).To(ContainSubstring(`Mixin "undefMixin" not found in`))
							Expect(warnings[0].FilePath).To(Equal("/foo.css"))
							Expect(warnings[0].Line).To(Equal(3))
							Expect(warnings[0].Column).To(Equal(1))
							Expect(warnings[0].Length).To(Equal(len("@mixin undefMixin")))
							Expect(warnings[0].LineText).To(ContainSubstring(`@mixin undefMixin from url`))
						})
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

					Describe("nested relative mixin", func() {
						AssertCode(`.nested-mixin { color: green; font-weight: bold; font-size: 99px; }`)
					})
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

					It("should generate a warning", func() {
						input := strings.TrimSpace(heredoc.Doc(`
							header {
								@mixin red from url("/unknown.css");
							}
						`))
						_, warnings, err := css.ParseCss(input, "/foo.css")
						Expect(err).NotTo(HaveOccurred())
						Expect(warnings).To(HaveLen(1))
						Expect(warnings[0].Text).To(Equal(`Could not resolve mixin file "/unknown.css" for mixin "red"`))
						Expect(warnings[0].FilePath).To(Equal("/foo.css"))
						Expect(warnings[0].Line).To(Equal(2))
						Expect(warnings[0].Column).To(Equal(1))
						Expect(warnings[0].Length).To(Equal(len("@mixin red")))
						Expect(warnings[0].LineText).To(ContainSubstring(`@mixin red from url("/unknown.css");`))
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

					It("should generate a warning", func() {
						input := strings.TrimSpace(heredoc.Doc(`
							header {
								@mixin unknown from url("/lib/mixins/colors.css");
							}
						`))
						_, warnings, err := css.ParseCss(input, "/foo.css")
						Expect(err).NotTo(HaveOccurred())
						Expect(warnings).To(HaveLen(1))
						Expect(warnings[0].Text).To(ContainSubstring(`Mixin "unknown" not found in`))
						Expect(warnings[0].FilePath).To(Equal("/foo.css"))
						Expect(warnings[0].Line).To(Equal(2))
						Expect(warnings[0].Column).To(Equal(1))
						Expect(warnings[0].Length).To(Equal(len("@mixin unknown")))
						Expect(warnings[0].LineText).To(ContainSubstring(`@mixin unknown from url`))
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
	})
})
