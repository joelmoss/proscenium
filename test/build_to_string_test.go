package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"path"
	"runtime"
	"testing"

	. "github.com/onsi/ginkgo/v2"
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
			AssertCode(`"sources": ["../../../lib/foo.js"]`)
			AssertCode(`"sources": ["../../../lib/foo.js"]`, Unbundle)
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

	EntryPoint("lib/importing/replacements.js", func() {
		AssertCode(`= Object.assign;`)
		AssertCode(`= Object.assign;`, Unbundle)
	})

	EntryPoint("lib/importing/application.js", func() {
		Describe("import '..'", func() {
			AssertCode(`console.log("/lib/index.js");`)
		})

		Describe("import '.'", func() {
			AssertCode(`console.log("/lib/importing/index.js");`)
		})

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

	Describe("aliases", func() {
		EntryPoint("lib/aliases/absolute_paths.js", func() {
			Describe("to unbundle: prefix", func() {
				BeforeEach(func() {
					types.Config.Aliases = map[string]string{
						"/lib/foo2.js": "unbundle:/lib/foo3.js",
					}
				})

				AssertCode(`import foo from "/lib/foo3.js";`)
				AssertCode(`import foo from "/lib/foo3.js";`, Unbundle)
			})

			Describe("to absolute path", func() {
				BeforeEach(func() {
					types.Config.Aliases = map[string]string{
						"/lib/foo2.js": "/lib/foo3.js",
					}
				})

				AssertCode(`console.log("/lib/foo3.js");`)
				AssertCode(`import foo from "/lib/foo3.js";`, Unbundle)
			})
		})

		EntryPoint("lib/aliases/relative_paths.js", func() {
			Describe("to unbundle: prefix", func() {
				BeforeEach(func() {
					types.Config.Aliases = map[string]string{
						"/lib/foo2.js": "unbundle:/lib/foo3.js",
					}
				})

				AssertCode(`import "/lib/foo3.js";`)
				AssertCode(`import "/lib/foo3.js";`, Unbundle)
			})

			Describe("to absolute path", func() {
				BeforeEach(func() {
					types.Config.Aliases = map[string]string{
						"/lib/foo2.js": "/lib/foo3.js",
					}
				})

				AssertCode(`console.log("/lib/foo3.js");`)
				AssertCode(`import "/lib/foo3.js";`, Unbundle)
			})
		})

		EntryPoint("lib/aliases/bare.js", func() {
			Describe("bare to unbundle: prefix", func() {
				BeforeEach(func() {
					types.Config.Aliases = map[string]string{
						"bare": "unbundle:/lib/foo.js",
					}
				})

				AssertCode(`import foo from "/lib/foo.js";`)
				AssertCode(`import foo from "/lib/foo.js";`, Unbundle)
			})

			Describe("bare to absolute path", func() {
				BeforeEach(func() {
					types.Config.Aliases = map[string]string{
						"bare": "/lib/foo4.js",
					}
				})

				AssertCode(`console.log("/lib/foo4.js");`)
				AssertCode(`import foo from "/lib/foo4.js";`, Unbundle)
			})
		})

		// EntryPoint("lib/aliases/packages.js", func() {
		// 	Describe("catches all with package prefix", func() {
		// 		BeforeEach(func() {
		// 			types.Config.Aliases = map[string]string{
		// 				"pkg/*": "unbundle:pkg/*",
		// 			}
		// 		})

		// 		AssertCode(`import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";`)
		// 		AssertCode(`import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";`, Unbundle)
		// 	})
		// })

		EntryPoint("lib/aliases/url.js", func() {
			Describe("bare to url", func() {
				BeforeEach(func() {
					types.Config.Aliases = map[string]string{
						"msw": "https://esm.sh/msw@1.3.2?bundle&dev",
					}
				})

				AssertCode(`import "https://esm.sh/msw@1.3.2?bundle&dev";`)
				AssertCode(`import "https://esm.sh/msw@1.3.2?bundle&dev";`, Unbundle)
			})
		})

		EntryPoint("lib/aliases/rubygems.js", func() {
			Describe("bare to unbundle: prefix", func() {
				BeforeEach(func() {
					addGem("gem2", "external")

					types.Config.Aliases = map[string]string{
						"@rubygems/gem2": "unbundle:@rubygems/gem2/lib/gem2/gem2.js",
					}
				})

				AssertCode(`import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";`)
				AssertCode(`import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";`, Unbundle)
			})

			Describe("@rubygems scope", func() {
				BeforeEach(func() {
					addGem("gem2", "external")

					types.Config.Aliases = map[string]string{
						"@rubygems/gem2": "@rubygems/gem2/lib/gem2/gem2.js",
					}
				})

				AssertCode(`console.log("gem2");`)
				AssertCode(`import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";`, Unbundle)
			})
		})

		EntryPoint("lib/aliases/bare_to_rubygems.js", func() {
			Describe("bare module to @rubygems path", func() {
				BeforeEach(func() {
					addGem("gem2", "external")

					types.Config.Aliases = map[string]string{
						"my-gem-alias": "@rubygems/gem2/lib/gem2/console.js",
					}
				})

				AssertCode(`console.log("gem2");`)
				AssertCode(`import "/node_modules/@rubygems/gem2/lib/gem2/console.js";`, Unbundle)
			})
		})

		EntryPoint("lib/aliases/bare_to_rubygems.css", func() {
			Describe("bare module to @rubygems CSS path", func() {
				BeforeEach(func() {
					addGem("gem2", "external")

					types.Config.Aliases = map[string]string{
						"gem-blue-alias": "@rubygems/gem2/lib/gem2/blue.css",
					}
				})

				AssertCode(`external/gem2/lib/gem2/blue.css`)
				AssertCode(`@import "/node_modules/@rubygems/gem2/lib/gem2/blue.css";`, Unbundle)
			})
		})
	})

	EntryPoint("lib/env_vars.js", func() {
		Describe("proscenium.env.* variables", func() {
			AssertCode(`console.log("testtest");`)
			AssertCode(`console.log("testtest");`, Unbundle)
			AssertCode(`console.log((void 0).UNKNOWN);`)
			AssertCode(`console.log((void 0).UNKNOWN);`, Unbundle)
		})
	})

	Describe("__filename and __dirname", func() {
		EntryPoint("lib/dirname_test.js", func() {
			AssertCode(`"/lib/dirname_test.js"`)
			AssertCode(`"/lib"`)
			AssertCode(`"/lib/dirname_test.js"`, Unbundle)
			AssertCode(`"/lib"`, Unbundle)
		})

		EntryPoint("lib/importing/app/dirname_nested.js", func() {
			AssertCode(`"/lib/importing/app/dirname_nested.js"`)
			AssertCode(`"/lib/importing/app"`)
			AssertCode(`"/lib/importing/app/dirname_nested.js"`, Unbundle)
			AssertCode(`"/lib/importing/app"`, Unbundle)
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
	})
})

func BenchmarkBuildToString(bm *testing.B) {
	_, filename, _, _ := runtime.Caller(0)
	types.Config.RootPath = path.Join(path.Dir(filename), "..", "fixtures", "dummy")
	types.Config.OutputDir = "public/assets"
	types.Config.Environment = types.TestEnv
	types.Config.InternalTesting = true

	for bm.Loop() {
		success, result, _ := b.BuildToString("lib/foo.js")

		if !success {
			panic("Build failed: " + result)
		}
	}
}
