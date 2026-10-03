package support

import (
	"errors"
	"fmt"
	"joelmoss/proscenium/internal/css"
	"joelmoss/proscenium/internal/types"
	"slices"

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
	Warnings []string
}

// No recover here: Ginkgo already reports a panic in a matcher as that one spec [PANICKED], with
// its stack. The parse's error is returned, though: the resolver recovers its own panics, and the
// parser keeps one as its error and leaves the failing mixin unexpanded - which a pass-through
// expectation would match. That branch has no spec: every panic the resolver recovers is a bug, and
// once the Environment zero-value underflow was fixed no input was left that triggers one.
func (matcher *BeParsedToMatcher) Match(actual interface{}) (bool, error) {
	if matcher.Config == nil {
		return false, errors.New("BeParsedTo needs the spec's config, but got nil")
	}

	// Taken as written: normalizeCss already ignores layout, and dedenting first changed what was
	// parsed - indentation inside a multi-line string or comment is part of its value.
	matcher.Input = actual.(string)

	parsed, warnings, err := css.ParseCss(matcher.Input, matcher.Path, matcher.Config)
	if err != nil {
		return false, fmt.Errorf("css.ParseCss failed for %s: %w", matcher.Path, err)
	}
	if err := matcher.checkWarnings(warnings); err != nil {
		return false, err
	}
	matcher.Output = parsed

	return normalizeCss(matcher.Output) == normalizeCss(matcher.Expected.(string)), nil
}

// The parse's warnings must equal the expected ones exactly, in order. An unresolved mixin is left
// in the output and reported only as a warning, so without this a pass-through expectation also
// passed when a broken config resolved nothing. Exact rather than a substring, since two mixin
// warnings share a first half (mixins.go). Returned as an error, so it fails a negated assertion
// too.
func (matcher *BeParsedToMatcher) checkWarnings(warnings []css.CssWarning) error {
	texts := make([]string, len(warnings))
	for i, w := range warnings {
		texts[i] = w.Text
	}

	ok := slices.Equal(texts, matcher.Warnings)
	if ok {
		return nil
	}

	return fmt.Errorf("css.ParseCss warned %q for %s, but the spec expected %q",
		texts, matcher.Path, matcher.Warnings)
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

// Parses with the spec's own config, so per-spec changes such as an added gem apply. `warnings` are
// the warnings the parse must produce, exactly and in order; none means none.
func BeParsedTo(expected interface{}, path string, cfg *types.ConfigT, warnings ...string) gomegaTypes.GomegaMatcher {
	return &BeParsedToMatcher{
		Path:     path,
		Config:   cfg,
		Expected: expected,
		Warnings: warnings,
	}
}
