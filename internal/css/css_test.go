package css_test

import (
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Css/Css", func() {
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
					`), "/foo.css")
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
						}
					`).To(BeParsedTo(`
						header {
							font-size: 20px;
							div { color: pink; }
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
							div { color: pink; }
						}
						header {
							@mixin large-button;
						}
					`).To(BeParsedTo(`
						header {
							appearance: none;
							font-size: 20px;
							div { color: pink; }
						}
					`, "/foo.css"))
				})
			})

			Describe("url", func() {
				It("undefined mixin is passed through", func() {
					Expect(`
						header {
							@mixin unknown from url('/config/button.mixin.css');
						}
					`).To(BeParsedTo(`
						header {
							@mixin unknown from url('/config/button.mixin.css');
						}
					`, "/foo.css"))
				})

				It("mixin is replaced with defined mixin", Pending, func() {
					Expect(`
						header {
							@mixin large-button from url('/config/button.mixin.css');
						}
					`).To(BeParsedTo(``, "/foo.css"))
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

			It("should rename classes", func() {
				Expect(`
					.title { color: green; }
				`).To(BeParsedTo(`
					.title43c30152 { color: green; }
				`))
			})

			It("should rename nested classes", func() {
				Expect(`
					.title {
						color: green;
						.subtitle { color: blue; }
					}
				`).To(BeParsedTo(`
					.title43c30152 {
						color: green;
						.subtitle43c30152 { color: blue; }
					}
				`))
			})

			It("should rename compound classes", func() {
				Expect(`
					.title.subtitle { color: green; }
				`).To(BeParsedTo(`
					.title43c30152.subtitle43c30152 { color: green; }
				`))
			})

			Describe("global function", func() {
				It("should not rename argument", func() {
					Expect(`
						.title { color: blue; }
						:global(.subtitle) { color: green; }
						.author { color: red; }
					`).To(BeParsedTo(`
						.title43c30152 { color: blue; }
						.subtitle { color: green; }
						.author43c30152 {	color: red; }
					`))
				})

				It("nested globals are ignored", Pending, func() {})

				It("nested classes should be renamed", func() {
					Expect(`
						:global(.subtitle) {
							color: green;
							.foo { color: orange; }
						}
					`).To(BeParsedTo(`
						.subtitle {
							color: green;
							.foo43c30152 { color: orange; }
						}
					`))
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
						.title43c30152 { color: blue; }
						.subtitle { color: green; }
						.author43c30152 { color: red; }
					`))
				})

				It("nested globals are ignored", Pending, func() {})

				It("nested classes should be renamed", func() {
					Expect(`
						:global .subtitle {
							color: green;
							.foo { color: orange; }
						}
					`).To(BeParsedTo(`
						.subtitle {
        			color: green;
        			.foo43c30152 { color: orange; }
						}
					`))
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
						.author43c30152 { color: red; }
					`))
				})

				It("nested globals are ignored", Pending, func() {})
			})
		})
	})
})
