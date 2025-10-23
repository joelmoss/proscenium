package proscenium_test

import (
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var assertCommonBuildBehaviour = func(build func(string, ...string) (bool, string, string)) {
	It("fails on unknown entrypoint", func() {
		success, result, _ := build("unknown.js")

		Expect(success).To(BeFalse())
		Expect(result).To(Equal("{\"ID\":\"\",\"PluginName\":\"\",\"Text\":\"Could not resolve \\\"unknown.js\\\"\",\"Location\":null,\"Notes\":null,\"Detail\":null}"))
	})

	It("fails when entrypoint is not a bare specifier", func() {
		for _, entryPoint := range [3]string{"/unknown.js", "./unknown.js", "../unknown.js"} {
			success, result, _ := build(entryPoint)

			Expect(success).To(BeFalse())
			Expect(result).To(Equal("{\"ID\":\"\",\"PluginName\":\"\",\"Text\":\"Could not resolve \\\"" + entryPoint + "\\\"\",\"Location\":null,\"Notes\":null,\"Detail\":\"Entrypoints must be bare specifiers\"}"))
		}
	})
}
