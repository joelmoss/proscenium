package builder_test

import (
	"joelmoss/proscenium/internal/builder"
	. "joelmoss/proscenium/internal/test"
	"os"
	"path"

	"github.com/evanw/esbuild/pkg/api"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/env", func() {
	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	build := func(path string) api.BuildResult {
		return builder.Build(builder.BuildOptions{
			Path: path,
			Root: root,
			Env:  2,
		})
	}

	It("exports requested env var as default", func() {
		result := build("lib/env/rails_env.js")

		Expect(result.OutputFiles[0].Contents).To(ContainCode(`
			var RAILS_ENV_default = "test";
		`))
	})

	When("env var is not set", func() {
		It("exports undefined", func() {
			result := build("lib/env/undefined_env.js")

			Expect(result.OutputFiles[0].Contents).To(ContainCode(`
				var UNDEF_default = UNDEF;
			`))
		})
	})
})
