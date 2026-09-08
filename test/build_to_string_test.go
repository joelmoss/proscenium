package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"
	"os"
	"path"
	"path/filepath"
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

		// Inlining is what lets one build hand back code and map together. Asking for the map
		// separately is a second complete build of the same module.
		Describe("inlined", func() {
			BeforeEach(func() {
				testConfig.SourcemapInline = true
			})

			It("embeds the map in the code", func() {
				_, result, _ := b.BuildToString("lib/foo.js", testConfig)

				Expect(result).To(ContainSubstring("//# sourceMappingURL=data:application/json;base64,"))
				Expect(result).NotTo(ContainSubstring("sourceMappingURL=foo.js.map"))
			})

			It("embeds the map in CSS too", func() {
				_, result, _ := b.BuildToString("lib/foo.css", testConfig)

				Expect(result).To(ContainSubstring("sourceMappingURL=data:application/json;base64,"))
				Expect(result).NotTo(ContainSubstring("sourceMappingURL=foo.css.map"))
			})

			It("refuses a request for the map on its own", func() {
				success, result, _ := b.BuildToString("lib/foo.js.map", testConfig)

				Expect(success).To(BeFalse())
				Expect(result).To(ContainSubstring("Source maps are inlined"))
			})
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
					testConfig.Aliases = map[string]string{
						"/lib/foo2.js": "unbundle:/lib/foo3.js",
					}
				})

				AssertCode(`import foo from "/lib/foo3.js";`)
				AssertCode(`import foo from "/lib/foo3.js";`, Unbundle)
			})

			Describe("to absolute path", func() {
				BeforeEach(func() {
					testConfig.Aliases = map[string]string{
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
					testConfig.Aliases = map[string]string{
						"/lib/foo2.js": "unbundle:/lib/foo3.js",
					}
				})

				AssertCode(`import "/lib/foo3.js";`)
				AssertCode(`import "/lib/foo3.js";`, Unbundle)
			})

			Describe("to absolute path", func() {
				BeforeEach(func() {
					testConfig.Aliases = map[string]string{
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
					testConfig.Aliases = map[string]string{
						"bare": "unbundle:/lib/foo.js",
					}
				})

				AssertCode(`import foo from "/lib/foo.js";`)
				AssertCode(`import foo from "/lib/foo.js";`, Unbundle)
			})

			Describe("bare to absolute path", func() {
				BeforeEach(func() {
					testConfig.Aliases = map[string]string{
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
		// 			testConfig.Aliases = map[string]string{
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
					testConfig.Aliases = map[string]string{
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

					testConfig.Aliases = map[string]string{
						"@rubygems/gem2": "unbundle:@rubygems/gem2/lib/gem2/gem2.js",
					}
				})

				AssertCode(`import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";`)
				AssertCode(`import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";`, Unbundle)
			})

			Describe("@rubygems scope", func() {
				BeforeEach(func() {
					addGem("gem2", "external")

					testConfig.Aliases = map[string]string{
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

					testConfig.Aliases = map[string]string{
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

					testConfig.Aliases = map[string]string{
						"gem-blue-alias": "@rubygems/gem2/lib/gem2/blue.css",
					}
				})

				AssertCode(`external/gem2/lib/gem2/blue.css`)
				AssertCode(`@import "/node_modules/@rubygems/gem2/lib/gem2/blue.css";`, Unbundle)
			})
		})

		// The aliased route into @rubygems resolution used to be a hand-copied branch that had
		// drifted from the top-level handler. These are the three gaps it had; each one is a
		// behaviour an alias could not reach but a directly-written specifier could.
		Describe("to an @rubygems path, via the shared resolver", func() {
			BeforeEach(func() {
				addGem("gem2", "external")
			})

			It("treats an aliased gem css module imported from js as a css module", func() {
				testConfig.Aliases = map[string]string{
					"my-gem-alias": "@rubygems/gem2/lib/gem2/styles.module.css",
				}

				_, result, _ := b.BuildToString("lib/aliases/rubygems_css_module.js", testConfig)

				// `new Proxy` is the class-name object. Without `PluginData.ImportedFromJs` the css
				// plugin never builds one, and the import received nothing usable.
				Expect(result).To(ContainCode(`new Proxy`))
				Expect(result).To(ContainCode(`.foo_`))
			})

			It("resolves an aliased gem path that has no extension", func() {
				testConfig.Aliases = map[string]string{
					"my-gem-alias": "@rubygems/gem2/lib/gem2/gem2",
				}

				success, result, _ := b.BuildToString("lib/aliases/bare_to_rubygems.js", testConfig)

				// Previously esbuild was handed the unresolved specifier itself and failed the build
				// with `Plugin "bundler" returned a non-absolute path`. Now the extensionless path
				// goes through esbuild, which finds `gem2.js` and bundles it.
				Expect(success).To(BeTrue(), result)
				Expect(result).To(ContainCode(`console.log("gem2");`))
			})

			It("honours the unbundle import attribute on an aliased gem path", func() {
				testConfig.Aliases = map[string]string{
					"my-gem-alias": "@rubygems/gem2/lib/gem2/console.js",
				}

				success, result, _ := b.BuildToString("lib/aliases/unbundle_attr.js", testConfig)

				// The attribute was not consumed, so esbuild rejected the build outright with
				// `Importing with the "unbundle" attribute is not supported`.
				Expect(success).To(BeTrue(), result)
				Expect(result).To(ContainCode(
					`import "/node_modules/@rubygems/gem2/lib/gem2/console.js";`))
			})

			// `IsRubyGem` tested the scope without stripping the optional prefixes first, so this
			// alias failed the guard, skipped gem resolution altogether, and left the browser a
			// bare `@rubygems/...` specifier it cannot resolve.
			It("resolves an alias onto an unbundle-prefixed gem path", func() {
				testConfig.Aliases = map[string]string{
					"my-gem-alias": "unbundle:@rubygems/gem2/lib/gem2/console.js",
				}

				success, result, _ := b.BuildToString("lib/aliases/bare_to_rubygems.js", testConfig)

				Expect(success).To(BeTrue(), result)
				Expect(result).To(ContainCode(
					`import "/node_modules/@rubygems/gem2/lib/gem2/console.js";`))
			})

			// An alias whose target is itself aliased, onto a DIFFERENT gem. The gem used to be
			// resolved before the alias was applied, so the first gem's root was joined with the
			// second gem's suffix, and the build failed on a path belonging to neither:
			// `<gem2-root>/@rubygems/gem1/lib/gem1/gem1.js`.
			It("follows an alias chain onto another gem", func() {
				addGem("gem1", "dummy/vendor")
				testConfig.Aliases = map[string]string{
					"my-gem-alias":                       "@rubygems/gem2/lib/gem2/console.js",
					"@rubygems/gem2/lib/gem2/console.js": "@rubygems/gem1/lib/gem1/gem1.js",
				}

				success, result, _ := b.BuildToString("lib/aliases/bare_to_rubygems.js", testConfig)

				Expect(success).To(BeTrue(), result)
				Expect(result).To(ContainCode(`console.log("gem1");`))
			})

			// Same chain, with the unbundle attribute on the import. Re-reading the prefix after
			// the alias used to ASSIGN the flag rather than raise it, clearing the attribute the
			// importer had set - and esbuild then rejected the build for an attribute nothing
			// had consumed.
			It("keeps the unbundle attribute across an alias chain", func() {
				testConfig.Aliases = map[string]string{
					"my-gem-alias":                       "@rubygems/gem2/lib/gem2/console.js",
					"@rubygems/gem2/lib/gem2/console.js": "@rubygems/gem2/lib/gem2/gem2.js",
				}

				success, result, _ := b.BuildToString("lib/aliases/unbundle_attr.js", testConfig)

				Expect(success).To(BeTrue(), result)
				Expect(result).To(ContainCode(
					`import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";`))
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
			testConfig.Bundle = true
		})

		assertCommonBuildBehaviour(func(path string) (bool, string, string) { return b.BuildToString(path, testConfig) })
	})

	Describe("bundle = false", func() {
		BeforeEach(func() {
			testConfig.Bundle = false
		})

		assertCommonBuildBehaviour(func(path string) (bool, string, string) { return b.BuildToString(path, testConfig) })
	})

	Describe("Write", func() {
		// Esbuild writes output files to OutputDir even though BuildToString only reads the
		// in-memory result, so every build leaves hashed files behind. Callers that just want the
		// string can turn that off.
		var outputPath = func() string {
			return filepath.Join(testConfig.RootPath, testConfig.OutputDir)
		}

		var outputFileCount = func() int {
			entries, err := os.ReadDir(outputPath())
			if err != nil {
				return 0
			}
			return len(entries)
		}

		BeforeEach(func() {
			os.RemoveAll(outputPath())
		})

		It("writes output files by default", func() {
			success, _, _ := b.BuildToString("lib/foo.js", testConfig)

			Expect(success).To(BeTrue())
			Expect(outputFileCount()).To(BeNumerically(">", 0))
		})

		It("writes nothing when Write is false, and still returns the code", func() {
			no := false
			testConfig.Write = &no

			success, code, _ := b.BuildToString("lib/foo.js", testConfig)

			Expect(success).To(BeTrue())
			Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
			Expect(outputFileCount()).To(Equal(0))
		})
	})

})

func BenchmarkBuildToString(bm *testing.B) {
	_, filename, _, _ := runtime.Caller(0)
	cfg := &types.ConfigT{
		RootPath:        path.Join(path.Dir(filename), "..", "fixtures", "dummy"),
		OutputDir:       "public/assets",
		Environment:     types.TestEnv,
		InternalTesting: true,
		CodeSplitting:   true,
		Bundle:          true,
	}

	for bm.Loop() {
		success, result, _ := b.BuildToString("lib/foo.js", cfg)

		if !success {
			panic("Build failed: " + result)
		}
	}
}
