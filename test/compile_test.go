package proscenium_test

import (
	"encoding/json"
	"os"
	"path/filepath"

	b "joelmoss/proscenium/internal/builder"

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
			root := filepath.Join(base, "app")
			keep := filepath.Join(base, "keep")
			Expect(os.MkdirAll(root, 0o755)).To(Succeed())
			Expect(os.MkdirAll(keep, 0o755)).To(Succeed())
			Expect(os.WriteFile(filepath.Join(keep, "precious.txt"), []byte("x"), 0o644)).To(Succeed())
			Expect(os.WriteFile(filepath.Join(root, "app.rb"), []byte("x"), 0o644)).To(Succeed())

			testConfig.RootPath = root
			testConfig.Precompile = []string{"./lib/foo.js"}
			testConfig.OutputDir = outputDir

			success, messages := b.Compile(testConfig)

			Expect(success).To(BeFalse())
			Expect(messages).To(ContainSubstring("Invalid output directory"))
			Expect(filepath.Join(root, "app.rb")).To(BeARegularFile())
			Expect(filepath.Join(keep, "precious.txt")).To(BeARegularFile())
		},
		Entry("empty", ""),
		Entry("the root itself", "."),
		Entry("the parent", ".."),
		Entry("a sibling of the root", "../keep"),
		Entry("a traversal hidden behind a subdirectory", "public/../../keep"),
	)

	It("reports a config that does not parse as a message", func() {
		var result struct{ Errors []esbuild.Message }
		Expect(json.Unmarshal([]byte(b.CompileErrorJSON("Invalid config", "detail")), &result)).To(Succeed())
		Expect(result.Errors[0].Text).To(Equal("Invalid config"))
		Expect(result.Errors[0].Detail).To(Equal("detail"))
	})
})

var _ = Describe("BuildToString", func() {
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
