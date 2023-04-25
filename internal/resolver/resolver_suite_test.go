package resolver_test

import (
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestResolver(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Proscenium resolver")
}
