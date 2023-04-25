package resolver_test

import (
	"joelmoss/proscenium/internal/resolver"
	"os"
	"path"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Resolver.Resolve", func() {
	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	resolve := func(path string) (string, error) {
		return resolver.Resolve(resolver.Options{
			Path: path,
			Root: root,
			Env:  2,
		})
	}

	When("leading slash", func() {
		It("resolves", func() {
			Expect(resolve("/lib/foo.js")).To(Equal("/lib/foo.js"))
		})
	})
})
