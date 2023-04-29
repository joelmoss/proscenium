package builder_test

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	. "joelmoss/proscenium/internal/test"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"

	"github.com/evanw/esbuild/pkg/api"
	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Internal/Builder.Build/env", func() {
	BeforeEach(func() {
		types.Env = types.TestEnv
		importmap.Contents = &types.ImportMap{}
		builder.DiskvCache.EraseAll()
	})
	AfterEach(func() {
		gock.Off()
	})

	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	build := func(path string) api.BuildResult {
		return builder.Build(builder.BuildOptions{
			Path: path,
			Root: root,
		})
	}

	It("exports requested env var as default", func() {
		Expect(build("lib/env/rails_env.js")).To(ContainCode(`
			var RAILS_ENV_default = "test";
		`))
	})

	When("env var is not set", func() {
		It("exports undefined", func() {
			Expect(build("lib/env/undefined_env.js")).To(ContainCode(`
				var UNDEF_default = UNDEF;
			`))
		})
	})
})
