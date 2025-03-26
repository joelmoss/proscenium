package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"
	"path"
	"runtime"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// Describe("nested", func() {
// 	AssertCode("relative", `console.log("pkg/nest/one.js");`)
// 	AssertCode("same package", `console.log("pkg/nest/two.js");`)
// 	AssertCode("different package", `console.log("pkg/three.js");`)
// 	AssertCode("app", `console.log("/lib/foo.js");`)
// })

var _ = Describe("BuildToString", func() {
	Describe("source maps", func() {
		EntryPoint("lib/foo.js.map", func() {
			AssertCode(`
				"sources": ["../../../lib/foo.js"],
				"sourcesContent": ["console.log('/lib/foo.js')\n"],
			`)
			AssertCode(`
				"sources": ["../../../lib/foo.js"],
				"sourcesContent": ["console.log('/lib/foo.js')\n"],
			`, Unbundle)
		})

		EntryPoint("lib/foo.js", func() {
			AssertCode("//# sourceMappingURL=foo.js.map")
			AssertCode("//# sourceMappingURL=foo.js.map", Unbundle)
		})

		EntryPoint("lib/foo.css", func() {
			AssertCode("/*# sourceMappingURL=foo.css.map */")
			AssertCode("/*# sourceMappingURL=foo.css.map */", Unbundle)
		})
	})

	EntryPoint("lib/importing/rjs.js", func() {
		AssertCode(`import "/constants.rjs";`)
		AssertCode(`import "/constants.rjs";`, Unbundle)
	})

	EntryPoint("lib/importing/application.js", func() {
		Describe("import absolute path", func() {
			AssertCode(`console.log("/lib/importing/app/one.js");`)
			AssertCode(`import "/lib/importing/app/one.js";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`console.log("/lib/importing/app/two.js");`)
				AssertCode(`import "/lib/importing/app/two.js";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`console.log("/lib/importing/app/index.js");`)
				AssertCode(`import "/lib/importing/app/index.js";`, Unbundle)
			})
		})

		Describe("import relative path", func() {
			AssertCode(`console.log("/lib/importing/app/three.js");`)
			AssertCode(`import "/lib/importing/app/three.js";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`console.log("/lib/importing/app/four.js");`)
				AssertCode(`import "/lib/importing/app/four.js";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`console.log("/lib/importing/app/five/index.js");`)
				AssertCode(`import "/lib/importing/app/five/index.js";`, Unbundle)
			})
		})
	})

	EntryPoint("lib/importing/url.js", func() {
		AssertCode(`import "https://proscenium.test/foo.js";`)
		AssertCode(`import "https://proscenium.test/foo.js";`, Unbundle)
	})

	EntryPoint("lib/importing/package.js", func() {
		Describe("import absolute path", func() {
			AssertCode(`console.log("pkg/one.js");`)
			AssertCode(`import "/node_modules/pkg/one.js";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`console.log("pkg/two.js");`)
				AssertCode(`import "/node_modules/pkg/two.js";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`console.log("pkg/index.js");`)
				AssertCode(`import "/node_modules/pkg/index.js";`, Unbundle)
			})
		})

		Describe("import pkg dependency", func() {
			AssertCode(`console.log("pkg_dep/index.js");`)
		})

		Describe("import app dependency", func() {
			AssertCode(`console.log("pnpm-file/one.js");`)
			AssertCode(`console.log("pnpm-file-ext/one.js");`)
			AssertCode(`console.log("pnpm-link/one.js");`)
			AssertCode(`console.log("pnpm-link-ext/one.js");`)
		})

		Describe("import app path", func() {
			AssertCode(`console.log("/lib/importing/app/one.js");`)
		})
	})

	EntryPoint("pkg/dependency", func() {
		AssertCode(`console.log("pkg_dep/index.js");`)
		AssertCode(`import "/node_modules/.pnpm/pkg@git+https+++git@gist.github.com`, Unbundle)
	})

	EntryPoint("lib/importing/pnpm_link.js", func() {
		Describe("import absolute path", func() {
			AssertCode(`console.log("pnpm-link/one.js");`)
			AssertCode(`import "/node_modules/pnpm-link/one.js";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`console.log("pnpm-link/two.js");`)
				AssertCode(`import "/node_modules/pnpm-link/two.js";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`console.log("pnpm-link/three/index.js");`)
				AssertCode(`import "/node_modules/pnpm-link/three/index.js";`, Unbundle)
			})
		})
	})

	EntryPoint("lib/importing/pnpm_link_external.js", func() {
		Describe("import absolute path", func() {
			AssertCode(`console.log("pnpm-link-ext/one.js");`)
			AssertCode(`import "/node_modules/pnpm-link-ext/one.js";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`console.log("pnpm-link-ext/two.js");`)
				AssertCode(`import "/node_modules/pnpm-link-ext/two.js";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`console.log("pnpm-link-ext/three/index.js");`)
				AssertCode(`import "/node_modules/pnpm-link-ext/three/index.js";`, Unbundle)
			})
		})
	})

	EntryPoint("lib/importing/pnpm_file.js", func() {
		Describe("import absolute path", func() {
			AssertCode(`console.log("pnpm-file/one.js");`)
			AssertCode(`import "/node_modules/pnpm-file/one.js";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`console.log("pnpm-file/two.js");`)
				AssertCode(`import "/node_modules/pnpm-file/two.js";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`console.log("pnpm-file/three/index.js");`)
				AssertCode(`import "/node_modules/pnpm-file/three/index.js";`, Unbundle)
			})
		})

		Describe("import pkg dependency", func() {
			AssertCode(`console.log("pkg_dep/index.js");`)
			AssertCode(`import "/node_modules/pnpm-file/dependency.js";`, Unbundle)
		})
	})

	EntryPoint("lib/importing/pnpm_file_external.js", func() {
		Describe("import absolute path", func() {
			AssertCode(`console.log("pnpm-file-ext/one.js");`)
			AssertCode(`import "/node_modules/pnpm-file-ext/one.js";`, Unbundle)

			Describe("without extension", func() {
				AssertCode(`console.log("pnpm-file-ext/two.js");`)
				AssertCode(`import "/node_modules/pnpm-file-ext/two.js";`, Unbundle)
			})

			Describe("without filename", func() {
				AssertCode(`console.log("pnpm-file-ext/three/index.js");`)
				AssertCode(`import "/node_modules/pnpm-file-ext/three/index.js";`, Unbundle)
			})
		})

		Describe("import pkg dependency", func() {
			AssertCode(`console.log("pkg_dep/index.js");`)
			AssertCode(`import "/node_modules/pnpm-file-ext/dependency.js";`, Unbundle)
		})
	})

	EntryPoint("lib/importing/unbundling.js", func() {
		BeforeEach(func() {
			importmap.NewJsonImportMap([]byte(`{
					"imports": {
						"three.js": "unbundle:/lib/importing/app/three.js"
					}
				}`))
		})

		AssertCode(`import "/lib/importing/app/one.js";`)
		AssertCode(`import "/lib/importing/app/two.js";`)
		AssertCode(`import "/lib/importing/app/three.js";`)
	})

	EntryPoint("lib/importing/import_map.js", func() {
		BeforeEach(func() {
			importmap.NewJsonImportMap([]byte(`{
					"imports": {
						"one.js": "/lib/importing/app/one.js"
					}
				}`))
		})

		AssertCode(`console.log("/lib/importing/app/one.js");`)
		AssertCode(`import "/lib/importing/app/one.js";`, Unbundle)
	})

	EntryPoint("lib/env_vars.js", func() {
		Describe("proscenium.env.* variables", func() {
			AssertCode(`console.log("testtest");`)
			AssertCode(`console.log("testtest");`, Unbundle)
			AssertCode(`console.log((void 0).UNKNOWN);`)
			AssertCode(`console.log((void 0).UNKNOWN);`, Unbundle)
		})
	})

	Describe("bundle = true", func() {
		BeforeEach(func() {
			types.Config.Bundle = true
		})

		assertCommonBuildBehaviour(b.BuildToString)
	})

	Describe("bundle = false", func() {
		BeforeEach(func() {
			types.Config.Bundle = false
		})

		assertCommonBuildBehaviour(b.BuildToString)

		It("does not build entrypoint with import map", func() {
			importmap.NewJsonImportMap([]byte(`{
				"imports": {
					"/lib/foo.js": "/lib/foo2.js"
				}
			}`))
			_, code := b.BuildToString("lib/foo.js")

			Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
		})
	})
})

func BenchmarkBuildToString(bm *testing.B) {
	_, filename, _, _ := runtime.Caller(0)
	types.Config.RootPath = path.Join(path.Dir(filename), "..", "fixtures", "dummy")
	types.Config.Environment = types.TestEnv

	for bm.Loop() {
		success, result := b.BuildToString("lib/foo.js")

		if !success {
			panic("Build failed: " + result)
		}
	}
}
