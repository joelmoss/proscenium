package proscenium_test

import (
	"joelmoss/proscenium/internal/utils"

	. "github.com/onsi/ginkgo/v2"
)

// An app's own `link:` and `file:` packages keep the URLs they have today once the app adopts gem
// dependency contexts (#154, Stage C). One real file is one module only for packages a gem
// context can share with the app; the app's own packages are not those, and their link paths
// are what pages already reference. The same entry points, with the same expectations, as
// build_to_string_test.go, but with a context map set.
var _ = Describe("An adopted app's own packages", func() {
	BeforeEach(func() {
		testConfig.DependencyContexts = map[string]string{
			"gem_npm": utils.JoinFsPath(testConfig.RootPath, ".proscenium", "packages", "gem_npm"),
		}
		testConfig.AppLocalPackages = []string{"pnpm-file", "pnpm-file-ext", "pnpm-link", "pnpm-link-ext"}
	})

	EntryPoint("lib/importing/pnpm_link.js", func() {
		AssertCode(`console.log("pnpm-link/one.js");`)
		AssertCode(`import "/node_modules/pnpm-link/one.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-link/two.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-link/three/index.js";`, Unbundle)
	})

	EntryPoint("lib/importing/pnpm_link_external.js", func() {
		AssertCode(`console.log("pnpm-link-ext/one.js");`)
		AssertCode(`import "/node_modules/pnpm-link-ext/one.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-link-ext/two.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-link-ext/three/index.js";`, Unbundle)
	})

	EntryPoint("lib/importing/pnpm_file.js", func() {
		AssertCode(`console.log("pnpm-file/one.js");`)
		AssertCode(`import "/node_modules/pnpm-file/one.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-file/two.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-file/three/index.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-file/dependency.js";`, Unbundle)
	})

	EntryPoint("lib/importing/pnpm_file_external.js", func() {
		AssertCode(`console.log("pnpm-file-ext/one.js");`)
		AssertCode(`import "/node_modules/pnpm-file-ext/one.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-file-ext/two.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-file-ext/three/index.js";`, Unbundle)
		AssertCode(`import "/node_modules/pnpm-file-ext/dependency.js";`, Unbundle)
	})
})
