package support

import (
	"errors"
	"fmt"
	"joelmoss/proscenium/internal/css"
	"joelmoss/proscenium/internal/types"

	"strings"

	"4d63.com/collapsewhitespace"
	"github.com/MakeNowJust/heredoc"
	"github.com/onsi/ginkgo/v2"
	"github.com/onsi/gomega/format"
	gomegaTypes "github.com/onsi/gomega/types"
	"github.com/sergi/go-diff/diffmatchpatch"
)

type BeParsedToMatcher struct {
	Path     string
	Input    string
	Output   string
	Config   *types.ConfigT
	Expected interface{}
}

// No recover here: Ginkgo already reports a panic in a matcher as that one spec [PANICKED], with
// its stack. The parse's error is returned, though: the resolver recovers its own panics, and the
// parser keeps one as its error and leaves the failing mixin unexpanded - which a pass-through
// expectation would match.
func (matcher *BeParsedToMatcher) Match(actual interface{}) (bool, error) {
	if matcher.Config == nil {
		return false, errors.New("BeParsedTo needs the spec's config, but got nil")
	}

	matcher.Input = strings.TrimSpace(heredoc.Doc(actual.(string)))
	matcher.Expected = strings.TrimSpace(heredoc.Doc(matcher.Expected.(string)))

	parsed, _, err := css.ParseCss(matcher.Input, matcher.Path, matcher.Config)
	if err != nil {
		return false, fmt.Errorf("css.ParseCss failed for %s: %w", matcher.Path, err)
	}
	matcher.Output = strings.TrimSpace(parsed)

	// Strip all newlines and tabs from the output and expected strings. This ensures that we are
	// comparing apples to apples.
	output := strings.ReplaceAll(matcher.Output, "\n", " ")
	output = strings.ReplaceAll(output, "\t", " ")
	output = collapsewhitespace.String(output)
	expected := strings.ReplaceAll(matcher.Expected.(string), "\n", " ")
	expected = strings.ReplaceAll(expected, "\t", " ")
	expected = collapsewhitespace.String(expected)

	return output == expected, nil
}

func (matcher *BeParsedToMatcher) FailureMessage(actual interface{}) string {
	return matcher.message(false)
}

func (matcher *BeParsedToMatcher) NegatedFailureMessage(actual interface{}) string {
	return matcher.message(true)
}

func (matcher *BeParsedToMatcher) message(isNegated bool) string {
	dmp := diffmatchpatch.New()
	diffs := dmp.DiffMain(matcher.Expected.(string), matcher.Output, false)
	diff := dmp.DiffPrettyText(diffs)
	ginkgo.GinkgoWriter.Printf("diff:\n\n%s\n\n", format.IndentString(diff, 1))

	to := ""
	if isNegated {
		to = "not "
	}

	return fmt.Sprintf("Expected:\n\n%s\n\n<<< %sto be parsed as:\n\n%s\n\n=== But was:\n\n%s\n",
		format.IndentString(matcher.Input, 2), to, format.IndentString(matcher.Expected.(string), 2),
		format.IndentString(matcher.Output, 2))
}

// Parses with the spec's own config, so per-spec changes such as an added gem apply.
func BeParsedTo(expected interface{}, path string, cfg *types.ConfigT) gomegaTypes.GomegaMatcher {
	return &BeParsedToMatcher{
		Path:     path,
		Config:   cfg,
		Expected: expected,
	}
}
