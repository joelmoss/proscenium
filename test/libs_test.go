package proscenium_test

import (
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(Libs)", func() {
	It("builds from lib/libs", func() {
		Expect(Resolve("@proscenium/react-manager/index.jsx")).To(Equal("/../../lib/proscenium/libs/react-manager/index.jsx"))
	})

	It("builds from lib/libs", func() {
		Expect(Build("lib/libs/stimulus_loading.js")).To(ContainCode(`
			function lazyLoadControllersFrom(under, application,
		`))
	})
})
