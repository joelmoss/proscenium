package proscenium_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"

	esbuild "github.com/joelmoss/esbuild-internal/api"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Compile", func() {
	// The branch nothing covered: esbuild itself failing on an entry point. Ruby's CompileError
	// exists to show exactly these messages.
	It("reports esbuild's errors when an entry point does not build", func() {
		testConfig.Precompile = []string{"./lib/css_modules/broken_import.js"}

		success, messages := b.Compile(testConfig)

		Expect(success).To(BeFalse())

		var result struct{ Errors []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Errors).To(HaveLen(1))
		Expect(result.Errors[0].Text).To(Equal(`Could not resolve "./missing.css"`))
		Expect(result.Errors[0].Location.File).To(Equal("lib/css_modules/broken_import.module.css"))
	})

	// The delete of old assets removes whatever OutputDir names. Empty joins to the application
	// itself (reachable through `Builder.compile(OutputDir: nil)`), and `..` segments are cleaned by
	// path.Join into something above it. Each of these deleted what it named before the guard.
	DescribeTable("refuses an output directory that is not strictly inside the root",
		func(outputDir string) {
			base := GinkgoT().TempDir()
			root := utils.JoinFsPath(base, "app")
			keep := utils.JoinFsPath(base, "keep")
			Expect(os.MkdirAll(root, 0o755)).To(Succeed())
			Expect(os.MkdirAll(keep, 0o755)).To(Succeed())
			Expect(os.WriteFile(utils.JoinFsPath(keep, "precious.txt"), []byte("x"), 0o644)).To(Succeed())
			Expect(os.WriteFile(utils.JoinFsPath(root, "app.rb"), []byte("x"), 0o644)).To(Succeed())

			testConfig.RootPath = root
			testConfig.Precompile = []string{"./lib/foo.js"}
			testConfig.OutputDir = outputDir

			success, messages := b.Compile(testConfig)

			Expect(success).To(BeFalse())
			Expect(messages).To(ContainSubstring("Invalid output directory"))
			Expect(utils.JoinFsPath(root, "app.rb")).To(BeARegularFile())
			Expect(utils.JoinFsPath(keep, "precious.txt")).To(BeARegularFile())
		},
		Entry("empty", ""),
		Entry("the root itself", "."),
		Entry("the parent", ".."),
		Entry("a sibling of the root", "../keep"),
		Entry("a traversal hidden behind a subdirectory", "public/../../keep"),
		Entry("an absolute path, which esbuild would write to as given", "/nonexistent-output-dir"),
	)

	// Judged by relative path, not string prefix: a root of "/" or "." has no "<root>/" prefix to
	// match, and a sibling that merely starts with the root's name is still outside it.
	DescribeTable("OutputDirUnderRoot",
		func(root string, outputDir string, want string, ok bool) {
			got, gotOK := b.OutputDirUnderRoot(&types.ConfigT{RootPath: root, OutputDir: outputDir})

			Expect(gotOK).To(Equal(ok))
			if ok {
				Expect(got).To(Equal(want))
			}
		},
		Entry("a directory under the root", "/app", "public/assets", "/app/public/assets", true),
		Entry("a nested directory with a redundant segment", "/app", "public/./x/../assets", "/app/public/assets", true),
		Entry("a directory under a root of /", "/", "public/assets", "/public/assets", true),
		Entry("a directory under a relative root", ".", "public/assets", "public/assets", true),
		Entry("empty", "/app", "", "", false),
		Entry("the root itself", "/app", ".", "", false),
		Entry("the parent", "/app", "..", "", false),
		Entry("a sibling whose name starts with the root's", "/app", "../app2", "", false),
		Entry("above a root of /", "/", "..", "", false),
		Entry("above a relative root", ".", "..", "", false),
		Entry("an absolute path elsewhere", "/app", "/etc", "", false),
		Entry("an absolute path that happens to be under the root", "/app", "/app/public/assets", "", false),
	)

	// Compile shares buildEnvVars with BuildToString, and had no spec with env vars set at all.
	It("defines env vars in precompiled output", func() {
		testConfig.Precompile = []string{"./lib/env_vars_all.js"}
		testConfig.EnvVars = map[string]string{"API_KEY": "it's x"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeTrue(), messages)

		outputs, err := filepath.Glob(utils.JoinFsPath(testConfig.RootPath, "public/assets/lib/env_vars_all-*.js"))
		Expect(err).NotTo(HaveOccurred())
		Expect(outputs).To(HaveLen(1))

		code, err := os.ReadFile(outputs[0])
		Expect(err).NotTo(HaveOccurred())
		Expect(string(code)).To(ContainSubstring(`"it's x"`))
	})

	// A CSS module imported from JS is built on its own, and its warnings were dropped whenever that
	// build succeeded: a stylesheet stopped at a mixin limit said nothing at all.
	It("passes on the warnings of a CSS module imported from JS", func() {
		dir := compileFixtures(map[string]string{
			"a.js":         `import s from "./a.module.css"; console.log(s)`,
			"a.module.css": ".a{@mixin nope;}",
		})
		testConfig.Precompile = []string{"./tmp/" + filepath.Base(dir) + "/a.js"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeTrue(), messages)

		var result struct{ Warnings []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Warnings).To(ContainElement(
			HaveField("Text", HavePrefix(`Mixin "nope" not defined`))))
	})

	// Each message carried its whole source line, and minified CSS or JS is one line: a hundred
	// warnings on a megabyte sent Ruby a hundred megabytes.
	It("leaves out the source line of a message on a line over 10 KiB", func() {
		dir := compileFixtures(map[string]string{
			"long.css":  "/*" + strings.Repeat("x", 1<<20) + "*/.a{@mixin nope;}",
			"short.css": ".b{@mixin nope;}",
		})
		root := "./tmp/" + filepath.Base(dir)
		testConfig.Precompile = []string{root + "/long.css", root + "/short.css"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeTrue(), messages)

		var result struct{ Warnings []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Warnings).To(HaveLen(2))
		for _, w := range result.Warnings {
			Expect(w.Location.Line).To(Equal(1))
			if strings.HasSuffix(w.Location.File, "long.css") {
				Expect(w.Location.LineText).To(BeEmpty())
			} else {
				Expect(w.Location.LineText).To(Equal(".b{@mixin nope;}"))
			}
		}
	})

	// esbuild notes on a message carry a line too: a CSS module's warnings each point at the JS that
	// imported it, and on one line of minified JS that is a megabyte a warning.
	It("leaves out the source line of a note on a line over 10 KiB", func() {
		dir := compileFixtures(map[string]string{
			"a.js":         `import s from "./a.module.css"; console.log(s); /*` + strings.Repeat("x", 1<<20) + `*/`,
			"a.module.css": ".a{@mixin nope;}",
		})
		testConfig.Precompile = []string{"./tmp/" + filepath.Base(dir) + "/a.js"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeTrue(), messages)

		var result struct{ Warnings []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Warnings).NotTo(BeEmpty())
		Expect(result.Warnings[0].Notes).NotTo(BeEmpty())
		for _, w := range result.Warnings {
			for _, n := range w.Notes {
				Expect(n.Location).NotTo(BeNil())
				Expect(n.Location.LineText).To(BeEmpty())
			}
		}
	})

	It("leaves out the source line of an error on a line over 10 KiB", func() {
		dir := compileFixtures(map[string]string{
			"long.css": "/*" + strings.Repeat("x", 1<<20) + `*/@import "./missing.css";`,
		})
		testConfig.Precompile = []string{"./tmp/" + filepath.Base(dir) + "/long.css"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeFalse())

		var result struct{ Errors []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Errors).To(HaveLen(1))
		Expect(result.Errors[0].Location.LineText).To(BeEmpty())
	})

	// esbuild's own warnings are not the parser's, so its cap never saw them: mixins expanding to
	// thousands of bad declarations sent Ruby a warning for each.
	It("reports at most 100 warnings, then how many more there were", func() {
		dir := compileFixtures(map[string]string{"a.css": ".a{" + strings.Repeat(":;", 150) + "}"})
		testConfig.Precompile = []string{"./tmp/" + filepath.Base(dir) + "/a.css"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeTrue(), messages)

		var result struct{ Warnings []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Warnings).To(HaveLen(101))
		Expect(result.Warnings[100].Text).To(Equal("50 more warning(s) not reported"))
	})

	// A warning names what it is about, and a name from the CSS has no length.
	It("cuts the text of a message at 10 KiB", func() {
		name := strings.Repeat("x", 20<<10)
		dir := compileFixtures(map[string]string{"a.css": ".a{@mixin " + name + ";}"})
		testConfig.Precompile = []string{"./tmp/" + filepath.Base(dir) + "/a.css"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeTrue(), messages)

		var result struct{ Warnings []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Warnings).To(HaveLen(1))
		Expect(result.Warnings[0].Text).To(HavePrefix(`Mixin "xxx`))
		Expect(len(result.Warnings[0].Text)).To(BeNumerically("<=", 10<<10))
	})

	// A cut inside a multi-byte character would reach Ruby as U+FFFD, which JSON encoding puts in
	// place of the half left behind. The plain-ASCII spec never splits a character.
	It("cuts the text of a message without leaving half a character", func() {
		name := strings.Repeat("é", 10<<10) // `Mixin "` is 7 bytes, so the 10 KiB cut splits an é
		dir := compileFixtures(map[string]string{"a.css": ".a{@mixin " + name + ";}"})
		testConfig.Precompile = []string{"./tmp/" + filepath.Base(dir) + "/a.css"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeTrue(), messages)

		var result struct{ Warnings []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Warnings).To(HaveLen(1))
		Expect(result.Warnings[0].Text).To(HavePrefix(`Mixin "éé`))
		Expect(len(result.Warnings[0].Text)).To(BeNumerically("<=", 10<<10))
		Expect(result.Warnings[0].Text).NotTo(ContainSubstring("�"))
	})

	// Errors are bounded as warnings are, but reach boundMessages by their own argument and kind.
	It("reports at most 100 errors, then how many more there were", func() {
		imports := make([]string, 150)
		for i := range imports {
			imports[i] = `@import "./missing` + strings.Repeat("x", i) + `.css";`
		}
		dir := compileFixtures(map[string]string{"a.css": strings.Join(imports, "\n")})
		testConfig.Precompile = []string{"./tmp/" + filepath.Base(dir) + "/a.css"}

		success, messages := b.Compile(testConfig)
		Expect(success).To(BeFalse())

		var result struct{ Errors []esbuild.Message }
		Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
		Expect(result.Errors).To(HaveLen(101))
		Expect(result.Errors[100].Text).To(Equal("50 more error(s) not reported"))
	})

	It("reports a config that does not parse as a message", func() {
		var result struct{ Errors []esbuild.Message }
		Expect(json.Unmarshal([]byte(b.CompileErrorJSON("Invalid config", "detail")), &result)).To(Succeed())
		Expect(result.Errors[0].Text).To(Equal("Invalid config"))
		Expect(result.Errors[0].Detail).To(Equal("detail"))
	})
})

var _ = Describe("BuildToString", func() {
	// The dev error page shows the failing message's line as is.
	It("leaves out the source line of a failure on a line over 10 KiB", func() {
		dir := compileFixtures(map[string]string{
			"long.css": "/*" + strings.Repeat("x", 1<<20) + `*/@import "./missing.css";`,
		})

		success, code, _ := b.BuildToString("tmp/"+filepath.Base(dir)+"/long.css", testConfig)
		Expect(success).To(BeFalse())

		var msg esbuild.Message
		Expect(json.Unmarshal([]byte(code), &msg)).To(Succeed())
		Expect(msg.Text).To(ContainSubstring("missing.css"))
		Expect(msg.Location.LineText).To(BeEmpty())
	})

	It("compiles!", func() {
		testConfig.Precompile = []string{
			"./app/models/**/*.js",
			"./app/models/**/*.jsx",
		}

		success, _ := b.Compile(testConfig)

		Expect(success).To(BeTrue())
	})

	It("handles css modules", func() {
		testConfig.Precompile = []string{
			"./app/components/css_module_import.js",
			"./app/components/css_module_import.module.css",
		}

		success, _ := b.Compile(testConfig)

		Expect(success).To(BeTrue())
	})
})

// Writes the given files to a fresh directory under the app's tmp, removed after the spec.
func compileFixtures(files map[string]string) string {
	dir, err := os.MkdirTemp(filepath.Join(testConfig.RootPath, "tmp"), "compile-")
	Expect(err).NotTo(HaveOccurred())
	DeferCleanup(os.RemoveAll, dir)

	for name, contents := range files {
		Expect(os.WriteFile(filepath.Join(dir, name), []byte(contents), 0o600)).To(Succeed())
	}

	return dir
}
