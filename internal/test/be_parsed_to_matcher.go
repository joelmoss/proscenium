package test

import (
	"fmt"
	"joelmoss/proscenium/internal/css"
	"os"
	"path"
	"runtime"
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
	Expected interface{}
}

var cwd, _ = os.Getwd()
var root string = path.Join(cwd, "../../", "test", "internal")

func (matcher *BeParsedToMatcher) Match(actual interface{}) (success bool, matchErr error) {
	matcher.Input = strings.TrimSpace(heredoc.Doc(actual.(string)))
	matcher.Expected = strings.TrimSpace(heredoc.Doc(matcher.Expected.(string)))

	matcher.Output, _ = css.ParseCss(matcher.Input, matcher.Path, root)
	matcher.Output = strings.TrimSpace(matcher.Output)

	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(runtime.Error); ok {
				success = false
				matchErr = nil
			}
		}
	}()

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
		to = "not"
	}

	return fmt.Sprintf("Expected:\n\n%s\n\n<<< %sto be parsed as:\n\n%s\n\n=== But was:\n\n%s\n",
		format.IndentString(matcher.Input, 2), to, format.IndentString(matcher.Expected.(string), 2),
		format.IndentString(matcher.Output, 2))
}

func BeParsedTo(expected interface{}, path string) gomegaTypes.GomegaMatcher {
	return &BeParsedToMatcher{
		Path:     path,
		Expected: expected,
	}
}
