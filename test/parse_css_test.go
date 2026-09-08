package proscenium_test

import (
	"joelmoss/proscenium/internal/css"
	. "joelmoss/proscenium/test/support"
	"path/filepath"
	"strings"
	"time"

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
					_, warnings, err := css.ParseCss(input, "/foo.css", testConfig)
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
							_, warnings, err := css.ParseCss(input, "/foo.css", testConfig)
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
						_, warnings, err := css.ParseCss(input, "/foo.css", testConfig)
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
						_, warnings, err := css.ParseCss(input, "/foo.css", testConfig)
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

			// Every one of these hung or panicked before the parser's iteration helpers took
			// ownership of the end of the stream. They are asserted through `parseWithDeadline`
			// because the tokenizer returns its end-of-input token forever once the input is
			// exhausted: a loop that fails to stop spins without allocating, so a regression would
			// wedge the suite rather than fail it.
			// A mixin cannot be expanded while it is already open. Each of these pushed a fresh
			// tokenizer per invocation and never returned, growing the output and the tokenizer
			// stack until the process died - the same class of hang as the truncated-input cases
			// below, reached by recursion rather than by end-of-stream.
			Describe("recursive mixins", func() {
				It("refuses a mixin that includes itself", func() {
					code, warnings := parseWithDeadline(
						"@define-mixin m{color:red;@mixin m; }\na{@mixin m; }", "/foo.css")

					Expect(code).To(Equal("\na{color:red;@mixin m;  }"))
					Expect(warnings).To(HaveLen(1))
					Expect(warnings[0].Text).To(Equal(`Mixin "m" includes itself`))
				})

				// No whitespace after the terminator, so the declaration's own stack entry is the
				// only thing standing between this and an unbounded expansion.
				It("refuses a self-including mixin with nothing after the terminator", func() {
					code, warnings := parseWithDeadline(
						"@define-mixin m{color:red;@mixin m;}a{@mixin m;}", "/foo.css")

					Expect(code).To(Equal("a{color:red;@mixin m;}"))
					Expect(warnings).To(HaveLen(1))
					Expect(warnings[0].Text).To(Equal(`Mixin "m" includes itself`))
				})

				It("refuses two mixin files that include each other through url()", func() {
					code, warnings := parseWithDeadline(
						`.x{@mixin a from url("/lib/mixins/cycle/a.css"); }`,
						filepath.Join(testConfig.RootPath, "foo.css"))

					// Both definitions expand once; the second lap back into `a` is refused.
					Expect(code).To(ContainSubstring("color:red;color:blue;"))
					Expect(warnings).To(HaveLen(1))
					Expect(warnings[0].Text).To(Equal(`Mixin "a" includes itself`))
				})

				It("still expands a mixin used twice, and one nested inside another", func() {
					code, warnings := parseWithDeadline(
						"@define-mixin i{color:red;}\n@define-mixin o{@mixin i; }\na{@mixin o; }\nb{@mixin i; }",
						"/foo.css")

					Expect(warnings).To(BeEmpty())
					Expect(code).To(ContainSubstring("a{color:red;"))
					Expect(code).To(ContainSubstring("b{color:red;"))
				})
			})

			// The token after a mixin's terminator used to be consumed by an eager skip, so a
			// declaration on the same line as `@mixin foo;` lost its first token: `a{@mixin m;
			// display:block;}` became `a{color:red;:block;}`, and `a{@mixin m;}` lost its closing
			// brace. Whitespace after the terminator masked it, which is why every fixture missed
			// it.
			Describe("the token after a mixin declaration", func() {
				It("keeps a declaration that follows on the same line", func() {
					Expect("@define-mixin m{color:red;}a{@mixin m;display:block;}").To(
						BeParsedTo("a{color:red;display:block;}", "/foo.css"))
				})

				It("keeps the closing brace when the mixin is the last thing in the rule", func() {
					Expect("@define-mixin m{color:red;}a{@mixin m;}").To(
						BeParsedTo("a{color:red;}", "/foo.css"))
				})

				It("keeps the token after an unresolved mixin, and emits it once", func() {
					Expect("a{@mixin nope;display:block;}").To(
						BeParsedTo("a{@mixin nope;display:block;}", "/foo.css"))
				})
			})

			Describe("truncated input", func() {
				It("passes through a mixin declaration with no terminating semicolon", func() {
					code, warnings := parseWithDeadline("@mixin foo", "/foo.css")

					Expect(code).To(Equal("@mixin foo"))
					Expect(warnings).To(HaveLen(1))
					Expect(warnings[0].Text).To(Equal(`Mixin "foo" not defined in "/foo.css"`))
				})

				It("consumes a mixin definition with no body", func() {
					code, warnings := parseWithDeadline("@define-mixin foo", "/foo.css")

					Expect(code).To(BeEmpty())
					Expect(warnings).To(BeEmpty())
				})

				It("consumes a mixin definition with an unclosed body", func() {
					code, warnings := parseWithDeadline("@define-mixin foo {", "/foo.css")

					Expect(code).To(BeEmpty())
					Expect(warnings).To(BeEmpty())
				})

				It("includes what it captured of an unclosed definition in a mixin file", func() {
					code, warnings := parseWithDeadline(
						"header {\n\t@mixin red from url('/lib/mixins/unterminated.css');\n}", "/foo.css")

					// The blank line is the newline that followed the `@mixin` declaration. It used
					// to be swallowed by the eager token skip in `handleNextToken`, and this
					// assertion pinned that; removing the skip restores it to the output.
					Expect(code).To(Equal("header {\n\ncolor: red;\n\n}"))
					Expect(warnings).To(BeEmpty())
				})
			})
		})
	})
})

// Parse the given CSS, failing the spec if it does not terminate. Returns the output and warnings.
func parseWithDeadline(input string, filePath string) (string, []css.CssWarning) {
	type parsed struct {
		code     string
		warnings []css.CssWarning
	}

	done := make(chan parsed, 1)

	go func() {
		defer GinkgoRecover()

		code, warnings, err := css.ParseCss(input, filePath, testConfig)
		Expect(err).NotTo(HaveOccurred())

		done <- parsed{code, warnings}
	}()

	select {
	case result := <-done:
		return result.code, result.warnings
	case <-time.After(5 * time.Second):
		Fail("ParseCss did not terminate within 5s")
		return "", nil
	}
}
