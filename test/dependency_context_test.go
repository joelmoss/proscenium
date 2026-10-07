package proscenium_test

import (
	"fmt"
	b "joelmoss/proscenium/internal/builder"
	r "joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/utils"
	"os"
	"path/filepath"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// Gem dependency contexts (#154), as Stage A proved them, against a pnpm-shaped
// tree written here rather than installed: the app has stage-a-dep 7.0.0, the gem's context has
// 6.0.0, and both link React to one store copy. The gem lives inside the app tree, so walking up
// from it reaches the app's node_modules first - the case the lookup has to get right (C49).
var _ = Describe("Gem dependency contexts", func() {
	const gem = "stage_a_widget_a"
	const reactBody = "react 18.3.1 module body"
	const reactURL = `"/node_modules/.pnpm/react@18.3.1/node_modules/react/index.js"`
	const contextURL = "/.proscenium/packages/" + gem + "/node_modules/stage-a-dep/index.js"

	var root, contextDir string

	write := func(path string, contents string) {
		full := filepath.Join(root, path)
		Expect(os.MkdirAll(filepath.Dir(full), 0o755)).To(Succeed())
		Expect(os.WriteFile(full, []byte(contents), 0o644)).To(Succeed())
	}

	pkg := func(dir string, name string, version string, body string) {
		write(dir+"/package.json", `{"name":"`+name+`","version":"`+version+`","main":"index.js"}`)
		write(dir+"/index.js", body)
	}

	link := func(target string, path string) {
		if err := os.Symlink(target, filepath.Join(root, path)); err != nil {
			Skip("symlinks unavailable: " + err.Error())
		}
	}

	build := func(path string) (bool, string) {
		ok, code, _ := b.BuildToString(path, testConfig)
		return ok, code
	}

	BeforeEach(func() {
		real, err := filepath.EvalSymlinks(GinkgoT().TempDir())
		Expect(err).NotTo(HaveOccurred())
		root = filepath.ToSlash(real)
		contextDir = root + "/.proscenium/packages/" + gem

		pkg("node_modules/.pnpm/react@18.3.1/node_modules/react", "react", "18.3.1",
			`export const marker = "`+reactBody+`"; export default { marker };`)
		link(".pnpm/react@18.3.1/node_modules/react", "node_modules/react")
		pkg("node_modules/stage-a-dep", "stage-a-dep", "7.0.0", `export default "app stage-a-dep 7.0.0";`)
		pkg("node_modules/only-app-has", "only-app-has", "1.0.0", `export default "app only";`)

		write(".proscenium/packages/"+gem+"/package.json", `{"name":"@rubygems/`+gem+`","private":true}`)
		pkg(".proscenium/packages/"+gem+"/node_modules/stage-a-dep", "stage-a-dep", "6.0.0",
			`export default "gem stage-a-dep 6.0.0";`)
		Expect(os.MkdirAll(contextDir+"/node_modules", 0o755)).To(Succeed())
		link("../../../../node_modules/.pnpm/react@18.3.1/node_modules/react",
			".proscenium/packages/"+gem+"/node_modules/react")

		write("vendor/"+gem+"/index.js",
			"import React from 'react'\nimport isNumber from 'stage-a-dep'\nexport { React, isNumber }\n")
		write("node_modules/stage-a-dep/style.module.css", ".appStyle { color: blue; }\n")
		write(".proscenium/packages/"+gem+"/node_modules/stage-a-dep/style.module.css", ".gemStyle { color: red; }\n")
		write("vendor/"+gem+"/styles.js", "export { default } from 'stage-a-dep/style.module.css'\n")
		write("node_modules/stage-a-dep/mixin.css", "@define-mixin pad { padding: 7px; }\n")
		write(".proscenium/packages/"+gem+"/node_modules/stage-a-dep/mixin.css", "@define-mixin pad { padding: 6px; }\n")
		write("vendor/"+gem+"/mixins.css", ".box { @mixin pad from url(\"stage-a-dep/mixin.css\"); }\n")
		write("vendor/"+gem+"/with_ext.js", "export { default } from 'stage-a-dep/index.js'\n")
		write("vendor/"+gem+"/undeclared.js", "export { default } from 'only-app-has'\n")
		write("vendor/"+gem+"/miss.js", "export { default } from 'nobody-has'\n")
		write("app/app.js", "import React from 'react'\n"+
			"import * as widget from '@rubygems/"+gem+"/index.js'\n"+
			"console.log(React === widget.React, widget.isNumber)\n")

		testConfig.RootPath = root
		testConfig.RubyGems = map[string]string{gem: root + "/vendor/" + gem}
		testConfig.DependencyContexts = map[string]string{gem: contextDir}
	})

	When("bundling", func() {
		It("resolves the gem's dependencies from its context", func() {
			_, code := build("node_modules/@rubygems/" + gem + "/index.js")

			Expect(code).To(ContainSubstring("gem stage-a-dep 6.0.0"))
			Expect(code).NotTo(ContainSubstring("app stage-a-dep 7.0.0"))
		})

		It("reaches the app's copy without the seam (the fixture's positive control)", func() {
			testConfig.DependencyContexts = nil
			_, code := build("node_modules/@rubygems/" + gem + "/index.js")

			Expect(code).To(ContainSubstring("app stage-a-dep 7.0.0"))
		})

		It("bundles one React for the app and the gem", func() {
			ok, code := build("app/app.js")

			Expect(ok).To(BeTrue(), code)
			Expect(strings.Count(code, reactBody)).To(Equal(1))
			Expect(code).To(ContainSubstring("gem stage-a-dep 6.0.0"))
		})

		// Walk-up from the context directory still applies (the plan's Lookup section): it is how
		// hoisted copies are found, and here it reaches a package only the app declares.
		It("walks up from the context to a package only the app declares", func() {
			_, code := build("node_modules/@rubygems/" + gem + "/undeclared.js")

			Expect(code).To(ContainSubstring("app only"))
		})

		It("names the gem and package when nothing provides it", func() {
			ok, code := build("node_modules/@rubygems/" + gem + "/miss.js")

			Expect(ok).To(BeFalse(), code)
			Expect(code).To(ContainSubstring(`gem \"` + gem + `\": could not resolve \"nobody-has\" from its dependency context`))
		})
	})

	When("unbundling", func() {
		BeforeEach(func() {
			testConfig.Bundle = false
		})

		It("serves the gem's dependency from its context and React from its real path", func() {
			_, code := build("node_modules/@rubygems/" + gem + "/index.js")

			Expect(code).To(ContainSubstring(`"` + contextURL + `"`))
			Expect(code).To(ContainSubstring(reactURL))
		})

		// C22: a dynamic import inside the nested copy keeps the nested copy's URL, which the
		// middleware serves (test/middleware_test.rb).
		It("loads a nested copy's dynamic import from the nested copy", func() {
			dep := ".proscenium/packages/" + gem + "/node_modules/stage-a-dep/"
			write(dep+"lazy.js", "export default 'lazy 6.0.0'\n")
			write(dep+"dynamic.js", "export const load = () => import('./lazy.js')\n")
			write("vendor/"+gem+"/dynamic.js", "export { load } from 'stage-a-dep/dynamic.js'\n")

			_, entry := build("node_modules/@rubygems/" + gem + "/dynamic.js")
			_, nested := build(dep + "dynamic.js")

			Expect(entry).To(ContainSubstring(`"/` + dep + `dynamic.js"`))
			Expect(nested).To(ContainSubstring(`import("/` + dep + `lazy.js")`))
		})

		It("gives the app the same React URL as the gem", func() {
			_, code := build("app/app.js")

			Expect(code).To(ContainSubstring(reactURL))
		})

		// pnpm's global virtual store keeps the real file outside the app root, where it has no URL.
		// The context's link then takes the app's link URL, so React is still one module.
		It("gives the app and the gem one React URL from a store outside the app root", func() {
			store, err := filepath.EvalSymlinks(GinkgoT().TempDir())
			Expect(err).NotTo(HaveOccurred())
			react := filepath.ToSlash(store) + "/react@18.3.1/node_modules/react"
			Expect(os.MkdirAll(react, 0o755)).To(Succeed())
			Expect(os.WriteFile(react+"/package.json", []byte(`{"name":"react","main":"index.js"}`), 0o644)).To(Succeed())
			Expect(os.WriteFile(react+"/index.js", []byte("export default 1\n"), 0o644)).To(Succeed())
			for _, path := range []string{"node_modules/react", ".proscenium/packages/" + gem + "/node_modules/react"} {
				Expect(os.Remove(filepath.Join(root, path))).To(Succeed())
				link(react, path)
			}
			appURL := `"/node_modules/react/index.js"`

			_, fromGem := build("node_modules/@rubygems/" + gem + "/index.js")
			_, fromApp := build("app/app.js")

			Expect(fromApp).To(ContainSubstring(appURL))
			Expect(fromGem).To(ContainSubstring(appURL))
		})

		// A Capistrano-style `current` symlink as the app root: real paths sit under the release
		// directory, and must still map to URLs under the root the app was given.
		It("gives the app and the gem one React URL when the app root is a symlink", func() {
			linked := filepath.ToSlash(filepath.Join(GinkgoT().TempDir(), "current"))
			if err := os.Symlink(root, linked); err != nil {
				Skip("symlinks unavailable: " + err.Error())
			}
			testConfig.RootPath = linked
			testConfig.RubyGems = map[string]string{gem: linked + "/vendor/" + gem}
			testConfig.DependencyContexts = map[string]string{gem: linked + "/.proscenium/packages/" + gem}

			_, fromGem := build("node_modules/@rubygems/" + gem + "/index.js")
			_, fromApp := build("app/app.js")

			Expect(fromGem).To(ContainSubstring(reactURL))
			Expect(fromApp).To(ContainSubstring(reactURL))
		})

		// The gem's import resolves to the real path, so the app's must too, or the browser loads
		// one module as two.
		It("gives an app import with an extension the same URL as the gem's", func() {
			write("vendor/"+gem+"/react_ext.js", "export { default } from 'react/index.js'\n")
			write("app/react_ext.js", "export { default } from 'react/index.js'\n")

			_, fromGem := build("node_modules/@rubygems/" + gem + "/react_ext.js")
			_, fromApp := build("app/react_ext.js")

			Expect(fromGem).To(ContainSubstring(reactURL))
			Expect(fromApp).To(ContainSubstring(reactURL))
		})

		// esbuild honours `exports`, which a file such as react's cjs build is left out of; served as
		// it always was, the file itself, at the one real-path URL for app and gem alike.
		It("serves a file a package's exports leave out, to the app and the gem alike", func() {
			write("node_modules/.pnpm/react@18.3.1/node_modules/react/package.json",
				`{"name":"react","version":"18.3.1","exports":{".":"./index.js","./package.json":"./package.json"}}`)
			write("node_modules/.pnpm/react@18.3.1/node_modules/react/cjs/dev.js", "export default 1\n")
			write("app/unexported.js", "export { default } from 'react/cjs/dev.js'\n")
			write("vendor/"+gem+"/unexported.js", "export { default } from 'react/cjs/dev.js'\n")
			url := `"/node_modules/.pnpm/react@18.3.1/node_modules/react/cjs/dev.js"`

			_, fromApp := build("app/unexported.js")
			ok, fromGem := build("node_modules/@rubygems/" + gem + "/unexported.js")

			Expect(fromApp).To(ContainSubstring(url))
			Expect(ok).To(BeTrue(), fromGem)
			Expect(fromGem).To(ContainSubstring(url))

			// Never a file outside node_modules.
			write("secret.js", "export default 1\n")
			write("app/escape.js", "export { default } from 'react/../../secret.js'\n")
			_, escaped := build("app/escape.js")

			Expect(escaped).NotTo(ContainSubstring(`"/secret.js"`))
		})

		// The same fallback for an asset that must be loaded rather than externalised: a CSS module
		// still gets its class-name proxy, and an SVG from JSX its component, not raw text.
		It("loads a CSS module or SVG the context package's exports leave out", func() {
			dep := ".proscenium/packages/" + gem + "/node_modules/stage-a-dep/"
			write(dep+"package.json", `{"name":"stage-a-dep","version":"6.0.0","exports":{".":"./index.js"}}`)
			write(dep+"icon.svg", `<svg xmlns="http://www.w3.org/2000/svg"><path d="M0"/></svg>`)
			write("vendor/"+gem+"/icon.jsx", "export { default } from 'stage-a-dep/icon.svg'\n")

			ok, css := build("node_modules/@rubygems/" + gem + "/styles.js")

			Expect(ok).To(BeTrue(), css)
			Expect(css).To(ContainSubstring("gemStyle"))
			Expect(css).NotTo(ContainSubstring(`from "/.proscenium/packages/`))

			ok, svg := build("node_modules/@rubygems/" + gem + "/icon.jsx")

			Expect(ok).To(BeTrue(), svg)
			Expect(svg).To(ContainSubstring(`("svg"`))
			Expect(svg).NotTo(ContainSubstring(`icon.svg"`))
		})

		It("resolves a bare import with an extension from the context", func() {
			_, code := build("node_modules/@rubygems/" + gem + "/with_ext.js")

			Expect(code).To(ContainSubstring(`"` + contextURL + `"`))
		})

		It("loads a CSS module the gem imports by package name from its context", func() {
			_, code := build("node_modules/@rubygems/" + gem + "/styles.js")

			Expect(code).To(ContainSubstring("gemStyle"))
			Expect(code).NotTo(ContainSubstring("appStyle"))
		})

		It("names the gem and package when nothing provides it", func() {
			ok, code := build("node_modules/@rubygems/" + gem + "/miss.js")

			Expect(ok).To(BeFalse(), code)
			Expect(code).To(ContainSubstring(`could not resolve \"nobody-has\" from its dependency context`))
		})

		// A store outside the app root (pnpm's global virtual store, say) has no URL, so the link
		// path, which has one, is kept.
		It("keeps the link path when the real path is outside the app root", func() {
			outside, err := filepath.EvalSymlinks(GinkgoT().TempDir())
			Expect(err).NotTo(HaveOccurred())
			Expect(os.WriteFile(filepath.Join(outside, "package.json"),
				[]byte(`{"name":"outside-dep","version":"1.0.0","main":"index.js"}`), 0o644)).To(Succeed())
			Expect(os.WriteFile(filepath.Join(outside, "index.js"), []byte("export default 1;"), 0o644)).To(Succeed())
			link(outside, ".proscenium/packages/"+gem+"/node_modules/outside-dep")
			write("vendor/"+gem+"/outside.js", "export { default } from 'outside-dep'\n")

			_, code := build("node_modules/@rubygems/" + gem + "/outside.js")

			Expect(code).To(ContainSubstring(`"/.proscenium/packages/` + gem + `/node_modules/outside-dep/index.js"`))
		})
	})

	// The plan's other resolve path: a CSS mixin looked up through resolver.Resolve.
	It("takes a gem's CSS mixin from its context", func() {
		ok, code := build("node_modules/@rubygems/" + gem + "/mixins.css")

		Expect(ok).To(BeTrue(), code)
		Expect(code).To(ContainSubstring("padding: 6px"))
		Expect(code).NotTo(ContainSubstring("padding: 7px"))
	})

	// C20 to C23: only a gem's external package lookup changes. Everything resolved inside the gem
	// - relative and self-referencing imports, CSS and CSS modules, fonts, SVG, dynamic imports,
	// source maps - builds the same with the map as without it, bundled or not.
	Describe("a gem's own files", func() {
		BeforeEach(func() {
			dir := "vendor/" + gem + "/"
			write(dir+"package.json", `{"name":"@rubygems/`+gem+`","exports":{".":"./index.js","./feature":"./helper.js"}}`)
			write(dir+"helper.js", "export default 'helper'\n")
			write(dir+"relative.js", "export { default } from './helper.js'\n")
			write(dir+"self.js", "export { default } from '@rubygems/"+gem+"/helper.js'\n")
			write(dir+"lazy.js", "export const load = () => import('./helper.js')\n")
			write(dir+"local.module.css", ".local { color: green; }\n")
			write(dir+"module.js", "import styles from './local.module.css'\nexport default styles.local\n")
			write(dir+"font.woff", "not a real font")
			write(dir+"icon.svg", `<svg xmlns="http://www.w3.org/2000/svg"></svg>`)
			write(dir+"assets.css", "@font-face { font-family: f; src: url('./font.woff'); }\n"+
				".icon { background: url('./icon.svg'); }\n@import './local.module.css';\n")
		})

		for _, entry := range []string{"relative.js", "self.js", "lazy.js", "module.js", "assets.css"} {
			for _, bundle := range []bool{true, false} {
				It(fmt.Sprintf("builds %s the same with the map (bundle: %v)", entry, bundle), func() {
					path := "node_modules/@rubygems/" + gem + "/" + entry
					testConfig.Bundle = bundle

					okWith, with := build(path)
					contexts := testConfig.DependencyContexts
					testConfig.DependencyContexts = nil
					okWithout, without := build(path)
					testConfig.DependencyContexts = contexts

					Expect(okWith).To(BeTrue(), with)
					Expect(okWithout).To(BeTrue(), without)
					Expect(with).To(Equal(without))
				})
			}
		}
	})

	// The gem-root regressions of 683dc375 (innermost nested gem root) and c9cb03c8 (prefix match,
	// not a pattern), applied to context routing: a file belongs to the innermost gem whose root
	// holds it, and `vendor/ab` is not a root of `vendor/abc`.
	Describe("which gem's context a file uses", func() {
		BeforeEach(func() {
			for _, g := range []string{"outer", "outer/inner", "ab", "ab+c"} {
				name := strings.ReplaceAll(g, "/", "_")
				write("vendor/"+g+"/index.js", "export { default } from 'stage-a-dep'\n")
				pkg(".proscenium/packages/"+name+"/node_modules/stage-a-dep", "stage-a-dep", "1.0.0",
					`export default "`+name+` context";`)
				testConfig.RubyGems[name] = root + "/vendor/" + g
				testConfig.DependencyContexts[name] = root + "/.proscenium/packages/" + name
			}
		})

		DescribeTable("routes to the innermost root that holds the file", func(gem string, expected string) {
			ok, code := build("node_modules/@rubygems/" + gem + "/index.js")

			Expect(ok).To(BeTrue(), code)
			Expect(code).To(ContainSubstring(expected + " context"))
		},
			Entry("outer", "outer", "outer"),
			Entry("a gem nested in another's tree", "outer_inner", "outer_inner"),
			Entry("ab", "ab", "ab"),
			Entry("a root that ab is a text prefix of", "ab+c", "ab+c"),
		)
	})

	It("resolves from the context outside a build", func() {
		urlPath, absPath, err := r.Resolve("stage-a-dep", root+"/vendor/"+gem+"/index.js", testConfig)

		Expect(err).NotTo(HaveOccurred())
		Expect(urlPath).To(Equal(contextURL))
		Expect(absPath).To(Equal(utils.JoinFsPath(contextDir, "node_modules/stage-a-dep/index.js")))
	})

	It("names the gem when resolving outside a build misses", func() {
		_, _, err := r.Resolve("nobody-has", root+"/vendor/"+gem+"/index.js", testConfig)

		Expect(err).To(MatchError(ContainSubstring(`gem "` + gem + `": could not resolve "nobody-has"`)))
	})

	It("keeps esbuild's diagnostic when the resolved package fails to parse", func() {
		pkg(".proscenium/packages/"+gem+"/node_modules/broken", "broken", "1.0.0", "export const = ;")

		_, _, err := r.Resolve("broken", root+"/vendor/"+gem+"/index.js", testConfig)

		Expect(err).To(HaveOccurred())
		Expect(err.Error()).NotTo(ContainSubstring("from its dependency context"))
	})

	It("still resolves an @rubygems specifier from a mapped gem to the gem", func() {
		urlPath, absPath, err := r.Resolve("@rubygems/"+gem+"/with_ext.js", root+"/vendor/"+gem+"/index.js", testConfig)

		Expect(err).NotTo(HaveOccurred())
		Expect(urlPath).To(Equal("/node_modules/@rubygems/" + gem + "/with_ext.js"))
		Expect(absPath).To(Equal(root + "/vendor/" + gem + "/with_ext.js"))
	})

	// A gem developed in its own repository is in its own bundle (`gemspec` in the Gemfile), so its
	// root is the app root, and node_modules sits inside it. A package installed there is not the
	// gem's code: its own bare imports resolve from where the package manager put them, beside it in
	// the store - not from the gem's context, which declares only the gem's direct dependencies, and
	// not from the app root, which here holds a different version of the same package.
	Describe("a package installed inside a gem whose root is the app root", func() {
		const owner = "node_modules/.pnpm/owner@1.0.0/node_modules/owner"
		// The URL's prefix is the gem's, as for any file under its root; the store path names the version.
		const trans = "/node_modules/.pnpm/trans@1.0.0/node_modules/trans/index.js"

		BeforeEach(func() {
			pkg("node_modules/.pnpm/trans@1.0.0/node_modules/trans", "trans", "1.0.0", `export default "trans 1.0.0";`)
			write("node_modules/.pnpm/trans@1.0.0/node_modules/trans/mixin.css", "@define-mixin pad { padding: 1px; }\n")
			pkg("node_modules/trans", "trans", "2.0.0", `export default "trans 2.0.0";`)
			write("node_modules/trans/mixin.css", "@define-mixin pad { padding: 2px; }\n")
			pkg(owner, "owner", "1.0.0", "export { default } from 'trans'\n")
			write(owner+"/mixins.css", ".box { @mixin pad from url(\"trans/mixin.css\"); }\n")
			link("../../trans@1.0.0/node_modules/trans", "node_modules/.pnpm/owner@1.0.0/node_modules/trans")
			link(".pnpm/owner@1.0.0/node_modules/owner", "node_modules/owner")
			link("../../../../node_modules/.pnpm/owner@1.0.0/node_modules/owner",
				".proscenium/packages/"+gem+"/node_modules/owner")
			write("lib/own.js", "export { default } from 'owner'\n")
			testConfig.RubyGems = map[string]string{gem: root}
		})

		for _, withMap := range []bool{true, false} {
			It(fmt.Sprintf("bundles the version installed beside it (map: %v)", withMap), func() {
				if !withMap {
					testConfig.DependencyContexts = nil
				}

				ok, code := build("lib/own.js")

				Expect(ok).To(BeTrue(), code)
				Expect(code).To(ContainSubstring("trans 1.0.0"))
				Expect(code).NotTo(ContainSubstring("trans 2.0.0"))
				Expect(code).NotTo(ContainSubstring(`from "trans"`))
			})
		}

		// Requested by its gem URL, the package is loaded in the rubygems namespace, whose loaders hand
		// its imports the file's real path. With the map, that path decides it is not the gem's; without
		// it, the step-1 lookup beside the file is the one that answers.
		for _, withMap := range []bool{true, false} {
			It(fmt.Sprintf("serves the version installed beside it by its gem URL (map: %v)", withMap), func() {
				if !withMap {
					testConfig.DependencyContexts = nil
				}
				testConfig.Bundle = false

				ok, code := build("node_modules/@rubygems/" + gem + "/" + owner + "/index.js")

				// The map makes it the store copy's real path; without it, owner's link to that copy.
				Expect(ok).To(BeTrue(), code)
				Expect(code).To(MatchRegexp(`\.pnpm/(trans|owner)@1\.0\.0/node_modules/trans/index\.js"`))
				Expect(code).NotTo(ContainSubstring(`/` + gem + `/node_modules/trans/index.js"`))
			})
		}

		// Map only: without contexts, a bare import with an extension takes the shortcut that serves
		// `/node_modules/<specifier>` unresolved, as it always has for an app without them.
		It("imports the version's stylesheet by its gem URL", func() {
			write("node_modules/.pnpm/trans@1.0.0/node_modules/trans/style.css", ".trans-one { color: red; }\n")
			write("node_modules/trans/style.css", ".trans-two { color: blue; }\n")
			write(owner+"/style.css", "@import 'trans/style.css';\n")
			testConfig.Bundle = false

			ok, code := build("node_modules/@rubygems/" + gem + "/" + owner + "/style.css")

			Expect(ok).To(BeTrue(), code)
			Expect(code).To(ContainSubstring(`.pnpm/trans@1.0.0/node_modules/trans/style.css"`))
			Expect(code).NotTo(ContainSubstring(`/` + gem + `/node_modules/trans/style.css"`))
		})

		It("resolves the version installed beside it outside a build", func() {
			urlPath, absPath, err := r.Resolve("trans", root+"/"+owner+"/index.js", testConfig)

			Expect(err).NotTo(HaveOccurred())
			Expect(urlPath).To(HaveSuffix(trans))
			Expect(absPath).To(Equal(root + trans))
		})

		// A package linked into the app from a store outside the app root, such as pnpm's global virtual
		// store: what it installed beside itself has no URL. Named, rather than the app root's copy.
		It("names the package when what is installed beside it is outside the app root", func() {
			store := root + "_store/owner@1.0.0/node_modules"
			for file, body := range map[string]string{
				"owner/package.json": `{"name":"owner","version":"1.0.0","main":"index.js"}`,
				"owner/index.js":     "export { default } from 'trans'\n",
				"trans/package.json": `{"name":"trans","version":"1.0.0","main":"index.js"}`,
				"trans/index.js":     `export default "trans 1.0.0";`,
			} {
				Expect(os.MkdirAll(filepath.Dir(store+"/"+file), 0o755)).To(Succeed())
				Expect(os.WriteFile(store+"/"+file, []byte(body), 0o644)).To(Succeed())
			}
			DeferCleanup(os.RemoveAll, root+"_store")
			link(store+"/owner", "node_modules/linked-owner")

			_, _, err := r.Resolve("trans", root+"/node_modules/linked-owner/index.js", testConfig)

			Expect(err).To(MatchError(`"trans" from "index.js" resolved outside the app root and every bundled gem`))
		})

		// Without contexts nothing else spells a real path back through the app root, so a root that
		// is itself a link (a Capistrano-style `current`, or on Windows a short or differently cased
		// spelling) must not turn the package directory's real path into one with no URL.
		It("resolves the version installed beside it when the app root is a link and there is no map", func() {
			current := root + "_current"
			Expect(os.Symlink(root, current)).To(Succeed())
			DeferCleanup(os.Remove, current)
			testConfig.RootPath = current
			testConfig.RubyGems = map[string]string{gem: current}
			testConfig.DependencyContexts = nil

			urlPath, absPath, err := r.Resolve("trans", current+"/"+owner+"/index.js", testConfig)

			// Without the map it keeps owner's link to the store copy, under the root's own spelling.
			Expect(err).NotTo(HaveOccurred())
			Expect(urlPath).To(MatchRegexp(`\.pnpm/(trans|owner)@1\.0\.0/node_modules/trans/index\.js$`))
			Expect(absPath).To(HavePrefix(current + "/node_modules/.pnpm/"))
		})

		// Resolving beside a package still walks up to the app's node_modules, so a peer only the
		// app installed - React here - is found as before.
		for _, withMap := range []bool{true, false} {
			It(fmt.Sprintf("still reaches a peer only the app root holds (map: %v)", withMap), func() {
				if !withMap {
					testConfig.DependencyContexts = nil
				}
				peerful := "node_modules/.pnpm/peerful@1.0.0/node_modules/peerful"
				pkg(peerful, "peerful", "1.0.0", "export { marker } from 'react'\n")
				write("lib/peer.js", "export { marker } from 'peerful'\n")
				link(".pnpm/peerful@1.0.0/node_modules/peerful", "node_modules/peerful")

				ok, code := build("lib/peer.js")
				_, absPath, err := r.Resolve("react", root+"/"+peerful+"/index.js", testConfig)

				Expect(ok).To(BeTrue(), code)
				Expect(code).To(ContainSubstring(reactBody))
				Expect(err).NotTo(HaveOccurred())
				Expect(absPath).To(HaveSuffix("/node_modules/react/index.js"))
			})
		}

		// The rule is for packages under the app root. A gem installed elsewhere that ships a package
		// in its own node_modules still hands that package the app's peers, which walking up from
		// the gem never reaches.
		It("still gives a package shipped inside a gem outside the app root the app's peer", func() {
			ext := root + "_ext"
			for file, body := range map[string]string{
				"index.js":                           "export { default } from './node_modules/peerless/index.js'\n",
				"node_modules/peerless/package.json": `{"name":"peerless","version":"1.0.0","main":"index.js"}`,
				"node_modules/peerless/index.js":     "export { default } from 'trans'\n",
			} {
				Expect(os.MkdirAll(filepath.Dir(ext+"/"+file), 0o755)).To(Succeed())
				Expect(os.WriteFile(ext+"/"+file, []byte(body), 0o644)).To(Succeed())
			}
			DeferCleanup(os.RemoveAll, ext)
			testConfig.RubyGems = map[string]string{gem: root, "ext": ext}
			testConfig.DependencyContexts = nil

			ok, code := build("node_modules/@rubygems/ext/index.js")

			Expect(ok).To(BeTrue(), code)
			Expect(code).To(ContainSubstring("trans 2.0.0"))
		})

		It("takes its CSS mixin from the version installed beside it by its gem URL", func() {
			testConfig.Bundle = false

			ok, code := build("node_modules/@rubygems/" + gem + "/" + owner + "/mixins.css")

			Expect(ok).To(BeTrue(), code)
			Expect(code).To(ContainSubstring("padding: 1px"))
			Expect(code).NotTo(ContainSubstring("padding: 2px"))
		})

		It("takes its CSS mixin from the version installed beside it", func() {
			ok, code := build(owner + "/mixins.css")

			Expect(ok).To(BeTrue(), code)
			Expect(code).To(ContainSubstring("padding: 1px"))
			Expect(code).NotTo(ContainSubstring("padding: 2px"))
		})
	})

	DescribeTable("which files are packages the app installed",
		func(rel string, rootSuffix string, expected bool) {
			testConfig.RootPath = root + rootSuffix

			Expect(utils.IsAppPackageFile(root+rel, testConfig)).To(Equal(expected))
		},
		Entry("a package's file", "/node_modules/x/index.js", "", true),
		Entry("a store copy's file", "/node_modules/.pnpm/x@1.0.0/node_modules/x/index.js", "", true),
		Entry("a context package's file", "/.proscenium/packages/g/node_modules/x/index.js", "", true),
		Entry("with a trailing slash on the root", "/node_modules/x/index.js", "/", true),
		Entry("the app's own file", "/lib/x.js", "", false),
		Entry("a directory that only ends in node_modules", "/my_node_modules/x.js", "", false),
		Entry("a sibling the root is a text prefix of", "_ext/node_modules/x/index.js", "", false),
		Entry("the root itself", "", "", false),
	)

	It("has no packages the app installed when no app root is set", func() {
		testConfig.RootPath = ""

		Expect(utils.IsAppPackageFile("/node_modules/x/index.js", testConfig)).To(BeFalse())
	})
})
