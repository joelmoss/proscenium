package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	r "joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/utils"
	"os"
	"path/filepath"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// The Stage A resolver seam for #154 (test/package_manager/stage_a/README.md), against a pnpm-shaped
// tree written here rather than installed: the app has stage-a-dep 7.0.0, the gem's context has
// 6.0.0, and both link React to one store copy. The gem lives inside the app tree, so walking up
// from it reaches the app's node_modules first - the case the seam has to get right (C49).
var _ = Describe("Stage A resolver seam", func() {
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
		write("vendor/"+gem+"/with_ext.js", "export { default } from 'stage-a-dep/index.js'\n")
		write("vendor/"+gem+"/undeclared.js", "export { default } from 'only-app-has'\n")
		write("vendor/"+gem+"/miss.js", "export { default } from 'nobody-has'\n")
		write("app/app.js", "import React from 'react'\n"+
			"import * as widget from '@rubygems/"+gem+"/index.js'\n"+
			"console.log(React === widget.React, widget.isNumber)\n")

		testConfig.RootPath = root
		testConfig.RubyGems = map[string]string{gem: root + "/vendor/" + gem}
		testConfig.StageAContexts = map[string]string{gem: contextDir}
	})

	When("bundling", func() {
		It("resolves the gem's dependencies from its context", func() {
			_, code := build("node_modules/@rubygems/" + gem + "/index.js")

			Expect(code).To(ContainSubstring("gem stage-a-dep 6.0.0"))
			Expect(code).NotTo(ContainSubstring("app stage-a-dep 7.0.0"))
		})

		It("reaches the app's copy without the seam (the fixture's positive control)", func() {
			testConfig.StageAContexts = nil
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

		It("gives the app the same React URL as the gem", func() {
			_, code := build("app/app.js")

			Expect(code).To(ContainSubstring(reactURL))
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
	})

	It("resolves from the context outside a build", func() {
		urlPath, absPath, err := r.Resolve("stage-a-dep", root+"/vendor/"+gem+"/index.js", testConfig)

		Expect(err).NotTo(HaveOccurred())
		Expect(urlPath).To(Equal(contextURL))
		Expect(absPath).To(Equal(utils.JoinFsPath(contextDir, "node_modules/stage-a-dep/index.js")))
	})

	It("still resolves an @rubygems specifier from a mapped gem to the gem", func() {
		urlPath, absPath, err := r.Resolve("@rubygems/"+gem+"/with_ext.js", root+"/vendor/"+gem+"/index.js", testConfig)

		Expect(err).NotTo(HaveOccurred())
		Expect(urlPath).To(Equal("/node_modules/@rubygems/" + gem + "/with_ext.js"))
		Expect(absPath).To(Equal(root + "/vendor/" + gem + "/with_ext.js"))
	})
})
