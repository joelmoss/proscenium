package css

import (
	"os"
	"testing"

	. "github.com/MakeNowJust/heredoc/dot"
	"github.com/gkampitakis/go-snaps/snaps"
)

func TestMain(t *testing.M) {
	v := t.Run()
	snaps.Clean(t)
	os.Exit(v)
}

func TestParseCss(t *testing.T) {
	parse := func(input string, path string) string {
		output, _ := ParseCss(D(input), path)
		t.Logf(output)
		return output
	}

	t.Run("should pass through regular css", func(t *testing.T) {
		snaps.MatchSnapshot(t, parse("body{}", "/foo.css"))
	})

	t.Run("css modules", func(t *testing.T) {
		t.Run("path is not a css module", func(t *testing.T) {
			snaps.MatchSnapshot(t, parse(`
				.title {
					color: green;
				}
			`, "/foo.css"))
		})

		t.Run("should rename classes", func(t *testing.T) {
			snaps.MatchSnapshot(t, parse(`
				.title {
					color: green;
				}
			`, "/foo.module.css"))
		})

		t.Run("should rename nested classes", func(t *testing.T) {
			snaps.MatchSnapshot(t, parse(`
				.title {
					color: green;
					.subtitle {
						color: blue;
					}
				}
			`, "/foo.module.css"))
		})

		t.Run("should rename compound classes", func(t *testing.T) {
			snaps.MatchSnapshot(t, parse(`
				.title.subtitle {
					color: green;
				}
			`, "/foo.module.css"))
		})

		t.Run("global function", func(t *testing.T) {
			t.Run("should not rename argument", func(t *testing.T) {
				snaps.MatchSnapshot(t, parse(`
					.title {
						color: blue;
					}
					:global(.subtitle) {
						color: green;
					}
					.author {
						color: red;
					}
				`, "/foo.module.css"))
			})

			t.Run("nested classes should be renamed", func(t *testing.T) {
				snaps.MatchSnapshot(t, parse(`
					:global(.subtitle) {
						color: green;
						.foo {
							color: orange;
						}
					}
				`, "/foo.module.css"))
			})
		})

		t.Run("global shorthand with argument", func(t *testing.T) {
			t.Run("should not rename argument", func(t *testing.T) {
				snaps.MatchSnapshot(t, parse(`
					.title {
						color: blue;
					}
					:global .subtitle {
						color: green;
					}
					.author {
						color: red;
					}
				`, "/foo.module.css"))
			})

			t.Run("nested classes should be renamed", func(t *testing.T) {
				snaps.MatchSnapshot(t, parse(`
					:global .subtitle {
						color: green;
						.foo {
							color: orange;
						}
					}
				`, "/foo.module.css"))
			})
		})

		t.Run("global shorthand without argument", func(t *testing.T) {
			t.Run("should rename all children", func(t *testing.T) {
				snaps.MatchSnapshot(t, parse(`
					:global {
						.subtitle {
							color: green;

							.foo {
								color: orange;
							}
						}
						.bar {
							color: blue;
						}
					}
					.author {
						color: red;
					}
				`, "/foo.module.css"))
			})
		})
	})

}
