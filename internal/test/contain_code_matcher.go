package test

import (
	"fmt"
	"strings"

	"4d63.com/collapsewhitespace"
	"github.com/onsi/gomega/format"
	"github.com/onsi/gomega/types"
)

type ContainCodeMatcher struct {
	code         string
	actualString string
}

func (matcher *ContainCodeMatcher) Match(actual interface{}) (success bool, err error) {
	actualString, ok := toString(actual)
	if !ok {
		return false, fmt.Errorf("ContainCode matcher requires a string.  Got:\n%s", format.Object(actual, 1))
	}

	matcher.actualString = strings.TrimSpace(actualString)

	return strings.Contains(collapsewhitespace.String(actualString), matcher.code), nil
}

func (matcher *ContainCodeMatcher) Message(isNegated bool) (message string) {
	to := ""
	if isNegated {
		to = "not"
	}

	return fmt.Sprintf("Expected:\n\n%s\n\n<<< %sto contain\n\n%s\n\n",
		format.IndentString(matcher.actualString, 2), to, format.IndentString(matcher.code, 2))
}

func (matcher *ContainCodeMatcher) FailureMessage(actual interface{}) (message string) {
	return matcher.Message(false)
}

func (matcher *ContainCodeMatcher) NegatedFailureMessage(actual interface{}) (message string) {
	return matcher.Message(true)
}

func ContainCode(expected string) types.GomegaMatcher {
	return &ContainCodeMatcher{
		code: strings.TrimSpace(collapsewhitespace.String(expected)),
	}
}

func toString(a interface{}) (string, bool) {
	aString, isString := a.(string)
	if isString {
		return aString, true
	}

	aBytes, isBytes := a.([]byte)
	if isBytes {
		return string(aBytes), true
	}

	return "", false
}
