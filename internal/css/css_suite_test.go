package css_test

import (
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestCss(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Proscenium CSS")
}
