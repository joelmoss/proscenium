package test

import (
	"fmt"
	"joelmoss/proscenium/internal/utils"
	"reflect"
	"strings"

	"4d63.com/collapsewhitespace"
	"github.com/MakeNowJust/heredoc"
	"github.com/evanw/esbuild/pkg/api"
	"github.com/onsi/gomega/format"
	"github.com/onsi/gomega/types"
)

type EqualCodeMatcher struct {
	code         string
	actualString string
}

func (matcher *EqualCodeMatcher) Match(actual interface{}) (success bool, err error) {
	if reflect.TypeOf(actual).String() == "api.BuildResult" {
		buildResult := actual.(api.BuildResult)

		if len(buildResult.Errors) > 0 {
			return false, fmt.Errorf("esbuild.BuildResult contains an error: \n%s", format.Object(buildResult.Errors, 1))
		}

		actual = buildResult.OutputFiles[0].Contents
	}

	actualString, ok := utils.ToString(actual)
	if !ok {
		return false, fmt.Errorf("EqualCode matcher requires a string.  Got:\n%s", format.Object(actual, 1))
	}

	matcher.actualString = strings.TrimSpace(heredoc.Doc(actualString))

	return collapsewhitespace.String(matcher.actualString) == collapsewhitespace.String(matcher.code), nil
}

func (matcher *EqualCodeMatcher) Message(isNegated bool) (message string) {
	to := ""
	if isNegated {
		to = "not"
	}

	return fmt.Sprintf("Expected:\n\n%s\n\n<<< %sto equal\n\n%s\n\n",
		format.IndentString(matcher.actualString, 2), to, format.IndentString(matcher.code, 2))
}

func (matcher *EqualCodeMatcher) FailureMessage(actual interface{}) (message string) {
	return matcher.Message(false)
}

func (matcher *EqualCodeMatcher) NegatedFailureMessage(actual interface{}) (message string) {
	return matcher.Message(true)
}

func EqualCode(expected string) types.GomegaMatcher {
	return &EqualCodeMatcher{
		code: strings.TrimSpace(heredoc.Doc(expected)),
	}
}
