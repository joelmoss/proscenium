package proscenium_test

import (
	"joelmoss/proscenium/internal/css"
	"joelmoss/proscenium/internal/utils"
	. "joelmoss/proscenium/test/support"
	"strings"
	"time"

	"github.com/MakeNowJust/heredoc"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(parseCss)", func() {
	Describe("ParseCss", func() {
		It("should pass through regular css", func() {
			Expect("body{}").To(BeParsedTo("body{}", "/foo.css", testConfig))
		})

		It("refuses a nil config", func() {
			success, err := BeParsedTo("body{}", "/foo.css", nil).Match("body{}")

			Expect(success).To(BeFalse())
			Expect(err).To(MatchError(ContainSubstring("needs the spec's config")))
		})

		// The tokenizer turned CR and CRLF into LF but not a form feed, which CSS treats the same.
		It("ends a hex escape at a form feed, as at any other whitespace", func() {
			Expect(".a\\2E\fb{color:red;}").To(BeParsedTo(`.a\2E b{color:red;}`, "/foo.css", testConfig))
		})

		// CRLF is folded first, so a CR then a form feed stays two newlines: the CR ends the escape
		// and the form feed separates the descendant.
		It("keeps a CR then a form feed as two newlines", func() {
			Expect(".a\\2E\r\fb{color:red;}").To(BeParsedTo(`.a\2E  b{color:red;}`, "/foo.css", testConfig))
		})

		// A newline inside a string or url(), or after a backslash, is a bad token: only malformed CSS
		// has one. The parser used to stop there and silently drop the rest of the stylesheet, and the
		// tokenizer cannot write one back as written (it decodes escapes and drops quotes and the
		// whitespace inside), so the input is returned unchanged for esbuild to report.
		DescribeTable("returns malformed CSS unchanged",
			func(input string) {
				output, _, err := css.ParseCss(input, "/foo.css", testConfig)

				Expect(err).NotTo(HaveOccurred())
				Expect(output).To(Equal(input))
			},
			Entry("string broken by a newline", "a{content:\"x\ny\";}\nb{color:blue}"),
			Entry("string holding an escaped newline", "a{content:\"\\a x\n;}\nb{color:blue}"),
			Entry("backslash before a newline", "a{color:red\\\n;}\nb{color:blue}"),
			Entry("url ending in a quote", "a{background:url(a\"b\")}\nb{color:blue}"),
			Entry("url with whitespace inside", "a{background:url(a\nb)}\nb{color:blue}"),
			Entry("url holding an escaped paren", "a{background:url(a\\29  b)}\nb{color:blue}"),
			Entry("bad token inside a mixin declaration", "a{@mixin red from url(a\nb);}\nb{color:blue}"),
			Entry("bad token after a mixin that resolves", "a{@mixin red from url(\"/lib/mixins/colors.css\");}\nb{content:\"x\ny\";}"),
			Entry("bad token in a local mixin that is never used", "@define-mixin m { content: \"x\n; }\na{color:red}"),
			Entry("bad token in a local mixin that is used", "@define-mixin m{background:url(a\"b\");color:red;}a{@mixin m;}"),
		)

		// A bad token in a mixin from another file leaves the stylesheet that uses it valid, so only
		// that mixin is refused, with a warning; returning the whole caller unchanged lost every other
		// expansion, and esbuild never sees the mixin file to report it.
		It("refuses a malformed mixin from another file, and still expands the rest", func() {
			file := utils.JoinFsPath(testConfig.RootPath, "lib/mixins/malformed.css")

			Expect("a{@mixin good from url(\"/lib/mixins/malformed.css\");}\nb{@mixin bad from url(\"/lib/mixins/malformed.css\");}").To(
				BeParsedTo("a{ color: green; } b{@mixin bad from url(\"/lib/mixins/malformed.css\");}", "/foo.css", testConfig,
					`Mixin "bad" in "`+file+`" is malformed CSS`))
		})

		// A @mixin declaration that is a mixin's last statement, with no semicolon, used to run on into
		// the stream that included the mixin, swallowing what followed, and resolve after the mixin had
		// closed, out of cycle detection's sight, so this looped. The body now gets the semicolon it
		// left out when defined, so the declaration ends inside the mixin and the cycle is caught.
		It("refuses a mixin including itself as its last statement without a semicolon", func() {
			code, warnings := parseWithDeadline("@define-mixin m{@mixin m}a{@mixin m;}", "/foo.css")

			Expect(code).To(Equal("a{@mixin m;}"))
			Expect(warnings).To(HaveLen(1))
			Expect(warnings[0].Text).To(Equal(`Mixin "m" includes itself`))
		})

		It("expands a mixin's last @mixin declaration without swallowing what follows", func() {
			Expect("@define-mixin outer { color: blue; @mixin inner }\n@define-mixin inner { color: green; }\n.a{ @mixin outer; padding: 0; }").To(
				BeParsedTo(".a{ color: blue; color: green; padding: 0; }", "/foo.css", testConfig))
		})

		// The tokenizer decodes `\c ` into a literal form feed and wrote it back raw, which CSS reads
		// as a newline, ending the string.
		It("keeps an escaped form feed in a mixin as an escape", func() {
			Expect("@define-mixin m{content:\"\\c \";}a{@mixin m;}").To(
				BeParsedTo(`a{content:"\c ";}`, "/foo.css", testConfig))
		})

		// CSS allows a block's last declaration to go without a semicolon. A mixin body was inserted as
		// written, so that declaration ran into the one after the `@mixin`: `a{color:redcolor:blue}`.
		It("ends a mixin body without a final semicolon before what follows", func() {
			Expect("@define-mixin m{color:red}a{@mixin m;color:blue}").To(
				BeParsedTo("a{color:red;color:blue}", "/foo.css", testConfig))
		})

		It("ends an imported mixin body without a final semicolon before what follows", func() {
			Expect("a{@mixin m from url(\"/lib/mixins/unterminated_body.css\");color:blue}").To(
				BeParsedTo("a{\n  color: red;\ncolor:blue}", "/foo.css", testConfig))
		})

		// Only a body whose last statement is a declaration needs the semicolon. A trailing comment is
		// not one: a rules mixin ending in a comment used to get `;` after it, which stuck to the next
		// selector at the root, so a browser dropped that rule.
		DescribeTable("terminating a mixin body",
			func(input, expected string) {
				Expect(input).To(BeParsedTo(expected, "/foo.css", testConfig))
			},
			Entry("empty", "@define-mixin m{}a{@mixin m;color:blue}", "a{color:blue}"),
			Entry("ending in a rule", "@define-mixin m{x{y:z}}a{@mixin m;color:blue}", "a{x{y:z}color:blue}"),
			Entry("already terminated", "@define-mixin m{color:red;}a{@mixin m;color:blue}", "a{color:red;color:blue}"),
			Entry("a declaration then a comment", "@define-mixin m{color:red/* c */}a{@mixin m;color:blue}", "a{color:red/* c */;color:blue}"),
			Entry("a rule then a comment, at the root", "@define-mixin m{a{color:red}/* c */}@mixin m;b{color:blue}", "a{color:red}/* c */b{color:blue}"),
			Entry("a rule then `-->`, at the root", "@define-mixin m{a{b:c}-->}@mixin m;d{e:f}", "a{b:c}-->d{e:f}"),
			Entry("a rule then `<!--`, at the root", "@define-mixin m{a{b:c}<!--}@mixin m;d{e:f}", "a{b:c}<!--d{e:f}"),
			Entry("a declaration then `-->`", "@define-mixin m{color:red -->}a{@mixin m;color:blue}", "a{color:red -->;color:blue}"),
		)

		// A @mixin declaration was read up to the next semicolon, so as a block's last statement with
		// none it ran past the block's `}` to the next `;` in the file, and all of it was discarded.
		Describe("a @mixin declaration ending its block without a semicolon", func() {
			It("keeps the block's closing brace and the rules after it", func() {
				Expect("@define-mixin m{color:red;}.a{@mixin m}.b{color:blue;}").To(
					BeParsedTo(".a{color:red;}.b{color:blue;}", "/foo.css", testConfig))
			})

			It("keeps them for a mixin from another file", func() {
				Expect(".a { @mixin red from url(\"/lib/mixins/colors.css\") }\n.b { color: red; }").To(
					BeParsedTo(".a {\n  color: red;\n}\n.b { color: red; }", "/foo.css", testConfig))
			})

			It("keeps them inside a mixin body", func() {
				Expect("@define-mixin i{color:red;}@define-mixin o{a{@mixin i}b{c:d;}}x{@mixin o;}y{e:f;}").To(
					BeParsedTo("x{a{color:red;}b{c:d;}}y{e:f;}", "/foo.css", testConfig))
			})

			// The brace is read twice, so it is counted back first. Without that, nesting stayed one
			// too low, a later root `@define-mixin` was not seen as one, and the rest was dropped.
			It("keeps the nesting count, so a later @define-mixin is still at the root", func() {
				Expect("@define-mixin m{color:red;}.a{@mixin m}@define-mixin n{color:blue;}.b{@mixin n;}").To(
					BeParsedTo(".a{color:red;}.b{color:blue;}", "/foo.css", testConfig))
				Expect("@define-mixin m{color:red;}@media print{.a{@mixin m}}@define-mixin n{color:blue;}.b{@mixin n;}").To(
					BeParsedTo("@media print{.a{color:red;}}.b{color:blue;}", "/foo.css", testConfig))
			})

			// Counting the pushed-back brace again matters inside a block too. At the root, the nesting
			// count's floor at zero hides a missing count, so only an enclosing block shows it.
			It("keeps the nesting count inside an enclosing block, so a @define-mixin there passes through", func() {
				Expect("@define-mixin m{color:red;}@media print{.a{@mixin m}@define-mixin n{x:y}}.b{@mixin n;}").To(
					BeParsedTo("@media print{.a{color:red;}@define-mixin n{x:y}}.b{@mixin n;}", "/foo.css", testConfig,
						`Mixin "n" not defined in "/foo.css"`))
			})

			It("keeps them for a mixin file that cannot be resolved", func() {
				code, warnings := parseWithDeadline(".a{@mixin m from url(\"/lib/mixins/nonexist.css\")}.b{c:d}", "/foo.css")

				Expect(code).To(Equal(".a{@mixin m from url(\"/lib/mixins/nonexist.css\")}.b{c:d}"))
				Expect(warnings).To(HaveLen(1))
			})

			It("keeps them for a mixin that is not defined", func() {
				Expect(".a{@mixin nope}.b{color:blue;}").To(
					BeParsedTo(".a{@mixin nope}.b{color:blue;}", "/foo.css", testConfig, `Mixin "nope" not defined in "/foo.css"`))
			})
		})

		// A `-->` or `<!--` after a body's last `@mixin` left it without a semicolon, so the
		// declaration ran to the end of the mixin, where the finished mixin was dropped from the stack
		// while the one it included expanded. Two mixins including each other then never met as a
		// cycle, and the parse never ended.
		It("refuses two mixins including each other, each ending in `-->`", func() {
			code, warnings := parseWithDeadline("@define-mixin a{@mixin b -->}@define-mixin b{@mixin a -->}x{@mixin a;}", "/foo.css")

			Expect(code).To(Equal("x{@mixin a -->;}"))
			Expect(warnings).To(HaveLen(1))
			Expect(warnings[0].Text).To(Equal(`Mixin "a" includes itself`))
		})

		// A mixin body cannot define a mixin. Expanded inside a rule it already passed through; at the
		// root, where the nesting is zero, it was defined. Either way it is refused with a warning.
		It("passes through a @define-mixin in a mixin expanded at the root", func() {
			Expect("@define-mixin w{@define-mixin z{q:r}}@mixin w;a{@mixin z;}").To(
				BeParsedTo("@define-mixin z{q:r}a{@mixin z;}", "/foo.css", testConfig,
					`Mixin "w" cannot define a mixin`, `Mixin "z" not defined in "/foo.css"`))
		})

		// A `}` with no block to close counted the nesting below zero, where nothing is ever at the
		// root again: a later `@define-mixin` captured to the end of the file, and all of it was
		// dropped without a warning. The brace is left for esbuild to report.
		Describe("a stray closing brace at the root", func() {
			It("keeps a later mixin definition and its use", func() {
				Expect("a{}}@define-mixin n{d:e}b{@mixin n;}").To(
					BeParsedTo("a{}}b{d:e;}", "/foo.css", testConfig))
			})

			It("keeps them when the stray brace comes first", func() {
				Expect("}@define-mixin n{d{e:f}}@mixin n;").To(
					BeParsedTo("}d{e:f}", "/foo.css", testConfig))
			})

			It("keeps them after a @mixin declaration ending its block", func() {
				Expect("a{@mixin m}}}}@define-mixin n{d:e}b{@mixin n;}").To(
					BeParsedTo("a{@mixin m}}}}b{d:e;}", "/foo.css", testConfig, `Mixin "m" not defined in "/foo.css"`))
			})
		})

		It("uses the last definition of a mixin in another file, even after a malformed one", func() {
			Expect("a{@mixin m from url(\"/lib/mixins/redefined.css\");}").To(
				BeParsedTo("a{ color: green; }", "/foo.css", testConfig))
		})

		// The input is parsed as written. Dedenting it first turned this continued string into "xy",
		// where the parser gives "x  y", and trimming dropped a trailing non-breaking space.
		It("parses the input as written, without dedenting or trimming it", func() {
			input := "a{content:\"x\\\n  y\";}"
			Expect(input).To(BeParsedTo(`a{content:"x  y";}`, "/foo.css", testConfig))

			success, err := BeParsedTo(`a{content:"xy";}`, "/foo.css", testConfig).Match(input)
			Expect(success).To(BeFalse())
			Expect(err).NotTo(HaveOccurred())

			success, err = BeParsedTo("a{}", "/foo.css", testConfig).Match("a{}\u00a0")
			Expect(success).To(BeFalse())
			Expect(err).NotTo(HaveOccurred())
		})

		It("ignores layout but not whitespace inside a quoted string", func() {
			Expect("a { content: \"x  y\"; }").To(BeParsedTo("a {\n\tcontent: \"x  y\";\n}", "/foo.css", testConfig))

			success, err := BeParsedTo(`a{content:"x y";}`, "/foo.css", testConfig).Match(`a{content:"x  y";}`)
			Expect(success).To(BeFalse())
			Expect(err).NotTo(HaveOccurred())
		})

		It("fails on a warning the spec did not expect, or an expected one that never came", func() {
			input := "a{@mixin nope;display:block;}"

			_, err := BeParsedTo(input, "/foo.css", testConfig).Match(input)
			Expect(err).To(MatchError(ContainSubstring(`Mixin \"nope\" not defined`)))

			_, err = BeParsedTo("body{}", "/foo.css", testConfig, "anything").Match("body{}")
			Expect(err).To(MatchError(ContainSubstring(`but the spec expected ["anything"]`)))
		})

		// Each actual is already in the parser's output form (strings in double quotes, escapes in
		// hex, one space of layout), so only normalizeCss decides whether it equals the expected.
		DescribeTable("compares strings, comments and escapes byte for byte, and layout loosely",
			func(actual string, expected string, equal bool) {
				success, err := BeParsedTo(expected, "/foo.css", testConfig).Match(actual)

				Expect(err).NotTo(HaveOccurred())
				Expect(success).To(Equal(equal))
			},
			Entry("escaped quote keeps the string open", `a{content:"x \"  y";}`, `a{content:"x \" y";}`, false),
			Entry("comment", `/* a  b */ a{}`, `/* a b */ a{}`, false),
			Entry("hex escape keeps its terminating space", `.a\2E  b{color:red;}`, `.a\2E b{color:red;}`, false),
			Entry("hex escape ended by CRLF", `.a\2E b{color:red;}`, ".a\\2E\r\nb{color:red;}", true),
			Entry("hex escape ended by a tab", `.a\2E b{color:red;}`, ".a\\2E\tb{color:red;}", true),
			Entry("hex escape ended by a form feed", `.a\2E b{color:red;}`, ".a\\2E\f b{color:red;}", false),
			Entry("non-hex escape keeps its character", `.\-1{color:red;}`, `.\+1{color:red;}`, false),
			Entry("layout collapses after a hex escape's terminator", `.a\2E  b{color:red;}`, ".a\\2E \n\t b{color:red;}", true),
		)

		It("fails on a warning whose text differs, or only begins the same", func() {
			input := "a{@mixin nope;display:block;}"

			_, err := BeParsedTo(input, "/foo.css", testConfig, "something else").Match(input)
			Expect(err).To(MatchError(ContainSubstring(`but the spec expected ["something else"]`)))

			// A substring would accept the start of the real warning; only the whole text matches.
			_, err = BeParsedTo(input, "/foo.css", testConfig, `Mixin "nope" not defined`).Match(input)
			Expect(err).To(MatchError(ContainSubstring("but the spec expected")))
		})

		It("does not match different output", func() {
			success, err := BeParsedTo("a{color:blue;}", "/foo.css", testConfig).Match("a{color:red;}")

			Expect(success).To(BeFalse())
			Expect(err).NotTo(HaveOccurred())
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
					`, "/foo.css", testConfig, `Mixin "foo" not defined in "/foo.css"`))
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
					`, "/foo.css", testConfig, `Mixin "foo" not defined in "/foo.css"`))
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
					`, "/foo.css", testConfig))
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
					`, "/foo.css", testConfig))
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

						// The stylesheet is under neither the app root nor a gem, so its relative
						// url() has no URL path. The warning used to carry no reason: Resolve handed
						// back a path under the app root that did not exist, and the failed read
						// fell through to the same message.
						It("warns with the resolver's reason when the stylesheet is outside the app root", func() {
							input := strings.TrimSpace(heredoc.Doc(`
								header {
									@mixin red from url("./colors.css");
								}
							`))
							stylesheet := utils.JoinFsPath(fixturesRoot, "external/one/outside.css")
							_, warnings, err := css.ParseCss(input, stylesheet, testConfig)
							Expect(err).NotTo(HaveOccurred())
							Expect(warnings).To(HaveLen(1))
							Expect(warnings[0].Text).To(ContainSubstring(`Could not resolve mixin file "./colors.css" for mixin "red": `))
							Expect(warnings[0].Text).To(ContainSubstring("outside the app root and every bundled gem"))
						})
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

						// Resolves only through the gem this spec added to its config.
						It("BeParsedTo sees the gem the spec added", func() {
							Expect(`a { @mixin mixin from url("@rubygems/gem1/mixin.css"); }`).To(
								BeParsedTo(`a { content: "@rubygems/gem1/mixin.css"; }`, "/foo.css", testConfig))
						})

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
					`, "/foo.css", testConfig))
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
					`, "/foo.css", testConfig, `Could not resolve mixin file "/unknown.css" for mixin "red"`))
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
					`, "/foo.css", testConfig,
							`Mixin "unknown" not found in "`+utils.JoinFsPath(testConfig.RootPath, "lib/mixins/colors.css")+`"`))
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
						`, "/foo.css", testConfig,
							`Mixin "purple" not found in "`+utils.JoinFsPath(testConfig.RootPath, "lib/mixins/colors.css")+`"`))
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
						`, "/foo.css", testConfig, `Mixin "blue" cannot define a mixin`))
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
					`, "/foo.css", testConfig))
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
						utils.JoinFsPath(testConfig.RootPath, "foo.css"))

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
						BeParsedTo("a{color:red;display:block;}", "/foo.css", testConfig))
				})

				It("keeps the closing brace when the mixin is the last thing in the rule", func() {
					Expect("@define-mixin m{color:red;}a{@mixin m;}").To(
						BeParsedTo("a{color:red;}", "/foo.css", testConfig))
				})

				It("keeps the token after an unresolved mixin, and emits it once", func() {
					Expect("a{@mixin nope;display:block;}").To(
						BeParsedTo("a{@mixin nope;display:block;}", "/foo.css", testConfig, `Mixin "nope" not defined in "/foo.css"`))
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
