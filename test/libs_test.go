package proscenium_test

import (
	. "joelmoss/proscenium/test/support"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Build(Libs)", func() {
	It("builds from lib/libs", func() {
		Expect(Build("@proscenium/test.js")).To(ContainCode(`
			console.log("/@proscenium/test.js");
		`))

		Expect(Build("@proscenium/ujs")).To(ContainCode(`
			const classPath = "/@proscenium/ujs/class.js";
		`))
	})

	It("builds to path", func() {
		_, code := BuildToPath("@proscenium/test.js")
		Expect(code).To(Equal("@proscenium/test.js::public/assets/@proscenium/test$SLCFI4GA$.js"))
	})
})
