package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/utils"
	. "joelmoss/proscenium/test/support"

	ast "github.com/joelmoss/esbuild-internal/ast"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("@rubygems scoped paths", func() {
	EntryPoint("node_modules/@rubygems/gem1/lib/gem1/gem1.js", func() {
		It("fails if gem not found", func() {
			success, _, _ := b.BuildToString(fileToAssertCode, testConfig)

			Expect(success).To(BeFalse())
		})

		AssertCode(`could not resolve Ruby gem \"gem1\"`)
	})

	EntryPoint("lib/rubygems/vendored.js", func() {
		It("fails if gem not found", func() {
			success, _, _ := b.BuildToString(fileToAssertCode, testConfig)

			Expect(success).To(BeFalse())
		})

		AssertCode(`could not resolve Ruby gem \"gem1\"`)
	})

	When("bundle = true", func() {
		BeforeEach(func() {
			testConfig.Bundle = true
		})

		Describe("external", func() {
			BeforeEach(func() {
				addGem("gem2", "external")
			})

			EntryPoint("node_modules/@rubygems/gem2/gem_dependency.js", func() {
				Describe("does not bundle bare import which is a dependency of the rubygem", func() {
					AssertCode(`import stringLength from "string-length";`)
					AssertCode(`import stringLength from "string-length";`, Unbundle)
				})
			})

			EntryPoint("node_modules/@rubygems/gem2/app_dependency.js", func() {
				Describe("resolves bare import which is a dependency of the app", func() {
					AssertCode(`console.log("pkg/index.js");`)
					AssertCode(`import "/node_modules/pkg/index.js";`, Unbundle)
				})
			})
		})

		Describe("inside root", func() {
			BeforeEach(func() {
				addGem("gem1", "dummy/vendor")
			})

			It("bundles", func() {
				_, code, _ := b.BuildToString("lib/rubygems/vendored.js", testConfig)

				Expect(code).To(ContainCode(`console.log("gem1");`))
			})

			It("bundles without extension", func() {
				_, code, _ := b.BuildToString("lib/rubygems/vendored_extensionless.js", testConfig)

				Expect(code).To(ContainCode(`console.log("gem1");`))
			})

			It("resolves entry point", func() {
				_, code, _ := b.BuildToString("node_modules/@rubygems/gem1/lib/gem1/gem1.js", testConfig)

				Expect(code).To(ContainCode(`console.log("gem1");`))
			})

			It("bundles from entrypoint", func() {
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code, _ := b.BuildToString("node_modules/@rubygems/gem3/lib/gem3/gem3.js", testConfig)

				Expect(code).To(ContainCode(`console.log("pkg/index.js")`))
				Expect(code).To(ContainCode(`console.log("gem3/imported")`))
				Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
				Expect(code).To(ContainCode(`console.log("gem3/foo")`))
				Expect(code).To(ContainCode(`console.log("gem3")`))
				Expect(code).To(ContainCode(`console.log("gem1")`))
				Expect(code).To(ContainCode(`console.log("gem4")`))
				Expect(code).To(ContainCode(`h1 { color: red; }`))
				Expect(code).To(ContainCode(`h2 { color: blue; }`))
				Expect(code).To(ContainCode(`h3 { color: green; }`))
				Expect(code).To(ContainCode(`console.log("lib/gem3/gem3")`))
			})

			It("bundles from import", func() {
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code, _ := b.BuildToString("lib/gems/gem3.js", testConfig)

				Expect(code).To(ContainCode(`console.log("pkg/index.js")`))
				Expect(code).To(ContainCode(`console.log("gem3/imported")`))
				Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
				Expect(code).To(ContainCode(`console.log("gem3/foo")`))
				Expect(code).To(ContainCode(`console.log("gem3")`))
				Expect(code).To(ContainCode(`console.log("gem1")`))
				Expect(code).To(ContainCode(`console.log("gem4")`))
				Expect(code).To(ContainCode(`h1 { color: red; }`))
				Expect(code).To(ContainCode(`h2 { color: blue; }`))
				Expect(code).To(ContainCode(`h3 { color: green; }`))
				Expect(code).To(ContainCode(`console.log("lib/gem3/gem3")`))
			})

			When("unbundle:* on import", func() {
				It("unbundles", func() {
					_, code, _ := b.BuildToString("lib/rubygems/unbundle_vendored.js", testConfig)

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
					`))
				})
			})

			It("does not bundle fonts", func() {
				_, code, _ := b.BuildToString("lib/rubygems/internal_fonts.css", testConfig)

				Expect(code).To(ContainCode(`url(/node_modules/@rubygems/gem1/somefont.woff2)`))
			})
		})

		Describe("outside root", func() {
			BeforeEach(func() {
				addGem("gem2", "external")
			})

			It("bundles", func() {
				_, code, _ := b.BuildToString("lib/rubygems/external.js", testConfig)

				Expect(code).To(ContainCode(`
					console.log("gem2");
				`))
			})

			It("bundles without extension", func() {
				_, code, _ := b.BuildToString("lib/rubygems/external_extensionless.js", testConfig)

				Expect(code).To(ContainCode(`
					console.log("gem2");
				`))
			})

			It("resolves entry point", func() {
				_, code, _ := b.BuildToString("node_modules/@rubygems/gem2/lib/gem2/gem2.js", testConfig)

				Expect(code).To(ContainCode(`
					console.log("gem2");
				`))
			})

			It("bundles from entrypoint", func() {
				addGem("gem1", "dummy/vendor")
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code, _ := b.BuildToString("node_modules/@rubygems/gem4/lib/gem4/gem4.js", testConfig)

				abspath := utils.JoinFsPath(testConfig.RootPath, "../external/gem4/lib/gem4/styles.module.css")
				hsh := ast.CssLocalHash(abspath)

				Expect(code).To(ContainCode(`d.querySelector("#_` + hsh + `")`))
				Expect(code).To(ContainCode(`e.id = "_` + hsh + `";`))
				Expect(code).To(ContainCode(`.name_` + hsh + `_---external-gem4-lib-gem4-styles-module`))

				Expect(code).To(ContainCode(`console.log("pkg/index.js")`))
				Expect(code).To(ContainCode(`console.log("gem4/imported")`))
				Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
				Expect(code).To(ContainCode(`console.log("gem4/foo")`))
				Expect(code).To(ContainCode(`console.log("gem4")`))
				Expect(code).To(ContainCode(`console.log("gem3")`))
				Expect(code).To(ContainCode(`console.log("gem2")`))
				Expect(code).To(ContainCode(`h1 { color: red; }`))
				Expect(code).To(ContainCode(`h2 { color: blue; }`))
				Expect(code).To(ContainCode(`h3 { color: green; }`))
				Expect(code).To(ContainCode(`console.log("lib/gem4/gem4")`))
			})

			It("bundles from import", func() {
				addGem("gem1", "dummy/vendor")
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code, _ := b.BuildToString("lib/gems/gem4.js", testConfig)

				abspath := utils.JoinFsPath(testConfig.RootPath, "../external/gem4/lib/gem4/styles.module.css")
				hsh := ast.CssLocalHash(abspath)

				Expect(code).To(ContainCode(`d.querySelector("#_` + hsh + `")`))
				Expect(code).To(ContainCode(`e.id = "_` + hsh + `";`))
				Expect(code).To(ContainCode(`.name_` + hsh + `_---external-gem4-lib-gem4-styles-module`))

				Expect(code).To(ContainCode(`console.log("pkg/index.js")`))
				Expect(code).To(ContainCode(`console.log("gem4/imported")`))
				Expect(code).To(ContainCode(`console.log("/lib/foo.js")`))
				Expect(code).To(ContainCode(`console.log("gem4/foo")`))
				Expect(code).To(ContainCode(`console.log("gem4")`))
				Expect(code).To(ContainCode(`console.log("gem3")`))
				Expect(code).To(ContainCode(`console.log("gem2")`))
				Expect(code).To(ContainCode(`h1 { color: red; }`))
				Expect(code).To(ContainCode(`h2 { color: blue; }`))
				Expect(code).To(ContainCode(`h3 { color: green; }`))
				Expect(code).To(ContainCode(`console.log("lib/gem4/gem4")`))
			})

			When("unbundle:* on import", func() {
				It("unbundles", func() {
					_, code, _ := b.BuildToString("lib/rubygems/unbundle_external.js", testConfig)

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
					`))
				})
			})

			When("unbundle:* relative import", func() {
				It("unbundles", func() {
					_, code, _ := b.BuildToString("lib/rubygems/external_unbundle_relative.js", testConfig)

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
					`))
				})
			})

			When("with { unbundle: 'true' } relative import", func() {
				It("unbundles", func() {
					_, code, _ := b.BuildToString("lib/rubygems/external_unbundle_with_relative.js", testConfig)

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
					`))
				})
			})

			When("unbundle:* same import", func() {
				It("unbundles", func() {
					_, code, _ := b.BuildToString("lib/rubygems/external_unbundle_same.js", testConfig)

					Expect(code).To(ContainCode(`
						import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
					`))
				})
			})

			It("does not bundle fonts", func() {
				_, code, _ := b.BuildToString("lib/rubygems/external_fonts.css", testConfig)

				Expect(code).To(ContainCode(`url(/node_modules/@rubygems/gem2/somefont.woff2)`))
			})
		})
	})

	When("bundle = false", func() {
		BeforeEach(func() {
			testConfig.Bundle = false
		})

		Describe("inside root", func() {
			BeforeEach(func() {
				addGem("gem1", "dummy/vendor")
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")
			})

			It("bundles", func() {
				_, code, _ := b.BuildToString("lib/rubygems/vendored.js", testConfig)

				Expect(code).To(ContainCode(`
					import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
				`))
			})

			It("bundles without extension", func() {
				_, code, _ := b.BuildToString("lib/rubygems/vendored_extensionless.js", testConfig)

				Expect(code).To(ContainCode(`
					import "/node_modules/@rubygems/gem1/lib/gem1/gem1.js";
				`))
			})

			It("resolves entry point", func() {
				_, code, _ := b.BuildToString("node_modules/@rubygems/gem1/lib/gem1/gem1.js", testConfig)

				Expect(code).To(ContainCode(`
					console.log("gem1");
				`))
			})

			It("resolves imports", func() {
				_, code, _ := b.BuildToString("node_modules/@rubygems/gem3/lib/gem3/gem3.js", testConfig)

				Expect(code).To(ContainCode(`import "/node_modules/pkg/index.js";`))
				Expect(code).To(ContainCode(`import imported from "/node_modules/@rubygems/gem3/lib/gem3/imported.js";`))
				Expect(code).To(ContainCode(`import "/lib/foo.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem3/lib/gem3/foo.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem3/lib/gem3/console.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem1/lib/gem1/console.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem4/lib/gem4/console.js";`))
				// A CSS module imported from JS is loaded even when unbundling, so it is no longer an
				// external import - the JS side needs the exported class-name Proxy.
				Expect(code).To(ContainCode(`const u = "/node_modules/@rubygems/gem3/lib/gem3/styles.module.css";`))
				Expect(code).To(ContainCode(`var styles_default = new Proxy({}, {`))
				Expect(code).To(ContainCode(`console.log("lib/gem3/gem3")`))
			})

			It("does not bundle fonts", func() {
				_, code, _ := b.BuildToString("lib/rubygems/internal_fonts.css", testConfig)

				Expect(code).To(ContainCode(`url(/node_modules/@rubygems/gem1/somefont.woff2)`))
			})
		})

		Describe("outside root", func() {
			BeforeEach(func() {
				addGem("gem2", "external")
			})

			It("bundles", func() {
				_, code, _ := b.BuildToString("lib/rubygems/external.js", testConfig)

				Expect(code).To(ContainCode(`
					import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
				`))
			})

			It("bundles without extension", func() {
				_, code, _ := b.BuildToString("lib/rubygems/external_extensionless.js", testConfig)

				Expect(code).To(ContainCode(`
					import "/node_modules/@rubygems/gem2/lib/gem2/gem2.js";
				`))
			})

			It("resolves entry point", func() {
				_, code, _ := b.BuildToString("node_modules/@rubygems/gem2/lib/gem2/gem2.js", testConfig)

				Expect(code).To(ContainCode(`
					console.log("gem2");
				`))
			})

			It("resolves import", func() {
				addGem("gem1", "dummy/vendor")
				addGem("gem3", "dummy/vendor")
				addGem("gem4", "external")

				_, code, _ := b.BuildToString("node_modules/@rubygems/gem4/lib/gem4/gem4.js", testConfig)

				Expect(code).To(ContainCode(`import "/node_modules/pkg/index.js";`))
				Expect(code).To(ContainCode(`import imported from "/node_modules/@rubygems/gem4/lib/gem4/imported.js";`))
				Expect(code).To(ContainCode(`import "/lib/foo.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem4/lib/gem4/foo.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem4/lib/gem4/console.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem3/lib/gem3/console.js";`))
				Expect(code).To(ContainCode(`import "/node_modules/@rubygems/gem2/lib/gem2/console.js";`))
				// A CSS module imported from JS is loaded even when unbundling, so it is no longer an
				// external import - the JS side needs the exported class-name Proxy.
				Expect(code).To(ContainCode(`const u = "/node_modules/@rubygems/gem4/lib/gem4/styles.module.css";`))
				Expect(code).To(ContainCode(`var styles_default = new Proxy({}, {`))
				Expect(code).To(ContainCode(`console.log("lib/gem4/gem4")`))
			})

			It("does not bundle fonts", func() {
				_, code, _ := b.BuildToString("lib/rubygems/external_fonts.css", testConfig)

				Expect(code).To(ContainCode(`url(/node_modules/@rubygems/gem2/somefont.woff2)`))
			})
		})
	})
})

var _ = Describe("@rubygems __filename and __dirname", func() {
	Describe("gem inside root (vendored)", func() {
		BeforeEach(func() {
			addGem("gem1", "dummy/vendor")
		})

		It("injects correct values into gem entry point", func() {
			_, code, _ := b.BuildToString("node_modules/@rubygems/gem1/lib/gem1/gem1.js", testConfig)

			Expect(code).To(ContainCode(`__filename = "@rubygems/gem1/lib/gem1/gem1.js"`))
			Expect(code).To(ContainCode(`__dirname = "@rubygems/gem1/lib/gem1"`))
		})

		It("injects correct values into app file that imports vendored gem", func() {
			_, code, _ := b.BuildToString("lib/rubygems/dirname_vendored.js", testConfig)

			Expect(code).To(ContainCode(`__filename = "@rubygems/gem1/lib/gem1/gem1.js"`))
			Expect(code).To(ContainCode(`__dirname = "@rubygems/gem1/lib/gem1"`))
			Expect(code).To(ContainCode(`__filename2 = "/lib/rubygems/dirname_vendored.js"`))
			Expect(code).To(ContainCode(`__dirname2 = "/lib/rubygems"`))
		})
	})

	Describe("gem outside root (external)", func() {
		BeforeEach(func() {
			addGem("gem2", "external")
		})

		It("injects correct values into gem entry point", func() {
			_, code, _ := b.BuildToString("node_modules/@rubygems/gem2/lib/gem2/gem2.js", testConfig)

			Expect(code).To(ContainCode(`__filename = "@rubygems/gem2/lib/gem2/gem2.js"`))
			Expect(code).To(ContainCode(`__dirname = "@rubygems/gem2/lib/gem2"`))
		})

		It("injects correct values into app file that imports external gem", func() {
			_, code, _ := b.BuildToString("lib/rubygems/dirname_test.js", testConfig)

			Expect(code).To(ContainCode(`__filename2 = "/lib/rubygems/dirname_test.js"`))
			Expect(code).To(ContainCode(`__dirname2 = "/lib/rubygems"`))
			Expect(code).To(ContainCode(`__filename = "@rubygems/gem2/lib/gem2/console.js"`))
			Expect(code).To(ContainCode(`__dirname = "@rubygems/gem2/lib/gem2"`))
		})
	})
})

// A gem stylesheet's imports resolve from the gem. The css plugin's OnLoad used to return the CSS
// without the ResolveDir and gem root that bundless had attached (esbuild drops a loader result
// that has no contents), so when unbundling every @import arrived with an empty ResolveDir and nil
// plugin data: the bare import below panicked at the gem-root fallback (`interface conversion:
// interface {} is nil`, recovered by esbuild into a failed build) and the relative one could not
// be joined. When bundling the file is loaded by its real path, which never had the problem.
var _ = Describe("gem stylesheet imports", func() {
	BeforeEach(func() {
		addGem("gem2", "external")
	})

	EntryPoint("node_modules/@rubygems/gem2/app/views/imports.css", func() {
		// A gem's bare import resolves from the gem's own node_modules in both modes (bareLookupDirs).
		// Bundling used to resolve it against the app root, so an app without the package kept the
		// @import for the browser while unbundling found the gem's copy. Unbundling is the path that
		// used to panic.
		Describe("bare import which is a dependency of the gem", func() {
			AssertCode(`.gem2_shadow { content: "open-props/shadows"; }`)
			AssertCode(`@import "/node_modules/@rubygems/gem2/node_modules/open-props/shadows.css";`, Unbundle)
		})

		Describe("relative import", func() {
			AssertCode(`.gem2_sibling { content: "@rubygems/gem2/app/views/sibling.css"; }`)
			AssertCode(`@import "/node_modules/@rubygems/gem2/app/views/sibling.css";`, Unbundle)
		})

		// A miss is not an error here: the browser reports the failed import. What must not
		// happen is a panic on the way to that answer.
		Describe("bare import that nothing provides", func() {
			AssertCode(`@import "does-not-exist";`)
			AssertCode(`@import "does-not-exist";`, Unbundle)
		})
	})

	// An import naming a file of the package goes through the same lookup: unbundling used to
	// point it at the app's node_modules without resolving it, so it got the app's copy, or none.
	EntryPoint("node_modules/@rubygems/gem2/app/views/imports_with_extension.css", func() {
		AssertCode(`.gem2_shadow { content: "open-props/shadows"; }`)
		AssertCode(`@import "/node_modules/@rubygems/gem2/node_modules/open-props/shadows.css";`, Unbundle)
	})

	// A file the package's `exports` leaves out is still served from the gem's own node_modules
	// when unbundling, as the app's shortcut serves the app's (fileUnderNodeModules).
	EntryPoint("node_modules/@rubygems/gem2/app/views/imports_hidden.css", func() {
		AssertCode(`@import "/node_modules/@rubygems/gem2/node_modules/expk/hidden.css";`, Unbundle)
	})

	// A gem's JS importing a bare CSS module from a package the app provides: unbundling loads it
	// through the css plugin, from the lookup's directory, rather than leaving the import raw.
	EntryPoint("node_modules/@rubygems/gem2/asset_peer.js", func() {
		AssertCode(`const u = "/node_modules/pnpm-link/three.module.css";`, Unbundle)
	})

	// The lookup's bound picks where resolution starts, never what it may return: the app's
	// `link:` package lives outside both the gem and the app, and a gem that leaves it to the app
	// still gets it.
	EntryPoint("node_modules/@rubygems/gem2/link_dependency.js", func() {
		AssertCode(`console.log("pnpm-link-ext/one.js");`)
	})

	// A package the gem ships resolves its own imports beside itself, then from the app: its
	// `browser` map disables `optional`, and `pnpm-link-ext` is a peer only the app provides, so
	// that import needs the second lookup directory.
	EntryPoint("node_modules/@rubygems/gem2/package_peer.js", func() {
		AssertCode(`console.log("pnpm-link-ext/one.js");`)
	})
	EntryPoint("node_modules/@rubygems/gem2/node_modules/peerk/index.js", func() {
		AssertCode(`import "/node_modules/pnpm-link-ext/one.js";`, Unbundle)
	})

	// A file another package's `exports` leaves out comes from the nearest node_modules above the
	// shipped package's file, not from a node_modules inside the importer's own directory.
	// gem2 lists React in its peerDependencies, and has a copy of its own in its node_modules, as
	// pnpm installs a peer for a gem developed locally. A peer is the app's to provide, so its
	// own files and the packages it ships both get the app's React (18.3.1): two copies on one
	// page break hooks.
	Describe("a peer the gem has its own copy of", func() {
		for _, entry := range []string{
			"node_modules/@rubygems/gem2/peer_react.js",
			"node_modules/@rubygems/gem2/node_modules/peerk/react.js",
		} {
			It("bundles the app's copy into "+entry, func() {
				_, code, _ := b.BuildToString(entry, testConfig)

				Expect(code).To(ContainSubstring("18.3.1"))
				Expect(code).NotTo(ContainSubstring("0.0.0-gem2"))
			})

			It("imports the app's copy from "+entry+" when unbundled", func() {
				_, code, _ := b.BuildToString(entry, configWithMarkers([]any{Unbundle}))

				Expect(code).To(ContainCode(`import { version } from "/node_modules/react/index.js";`))
			})
		}
	})

	EntryPoint("node_modules/@rubygems/gem2/node_modules/peerk/styles.css", func() {
		AssertCode(`@import "/node_modules/@rubygems/gem2/node_modules/expk/hidden.css";`, Unbundle)
	})
})

func addGem(name string, path string) {
	if testConfig.RubyGems == nil {
		testConfig.RubyGems = map[string]string{}
	}

	testConfig.RubyGems[name] = utils.JoinFsPath(fixturesRoot, path, name)
}
