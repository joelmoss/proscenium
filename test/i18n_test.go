package proscenium_test

import (
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"
	"os"
	"path/filepath"
	"testing"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("b.BuildToString(i18n)", func() {
	It("exports json", func() {
		_, code, _ := b.BuildToString("lib/i18n/benchmark/index.js", testConfig)

		Expect(code).To(ContainCode(`
			{ firstName: "Joel", foo: { bar: { baz: 1 } }, lastName: "Moss" }
		`))
	})

	// The locale cache used to be three globals with three independent write points, and the
	// directory mtime was recorded before any file was read - so a file that failed to parse
	// published the new directory mtime beside the old payload. Fixing the file's contents
	// afterwards does not change the directory mtime, which left nothing for the change detector
	// to notice and the stale payload served for the life of the process.
	It("recovers when an invalid locale file is fixed in place", func() {
		localeFile := filepath.Join(testConfig.RootPath, "config", "locales", "zz_added.yml")
		// RemoveAll, not Remove: this is registered before the file exists, so an early failure
		// below would otherwise fail the cleanup too and mask the real one.
		DeferCleanup(func() {
			Expect(os.RemoveAll(localeFile)).To(Succeed())
		})

		// Build once so there is something cached to go stale.
		success, _, _ := b.BuildToString("lib/i18n/benchmark/index.js", testConfig)
		Expect(success).To(BeTrue())

		// Adding the file changes the directory mtime; the build then fails on the YAML.
		Expect(os.WriteFile(localeFile, []byte("en:\n  added_key: \"unterminated\n"), 0o644)).To(Succeed())

		success, result, _ := b.BuildToString("lib/i18n/benchmark/index.js", testConfig)
		Expect(success).To(BeFalse())
		Expect(result).To(ContainSubstring("found unexpected end of stream"))

		// Fix the contents only. The directory mtime does not move, so recovery depends on the
		// failed build not having published anything.
		Expect(os.WriteFile(localeFile, []byte("en:\n  added_key: fixed\n"), 0o644)).To(Succeed())

		success, code, _ := b.BuildToString("lib/i18n/benchmark/index.js", testConfig)
		Expect(success).To(BeTrue())
		Expect(code).To(ContainSubstring(`addedKey: "fixed"`))
	})

	// The cache is keyed by locales directory because one process builds several apps - the suite
	// itself does. Both directories are given the same mtime deliberately: with distinct mtimes the
	// change detector rebuilds anyway and hides the missing key, so this pins the keying rather
	// than the coincidence that usually covers for it.
	It("keeps each app root's locales separate", func() {
		stamp := time.Now().Add(-time.Hour)

		rootFor := func(name string) string {
			root, err := os.MkdirTemp("", "proscenium-i18n-"+name)
			Expect(err).NotTo(HaveOccurred())
			DeferCleanup(func() {
				Expect(os.RemoveAll(root)).To(Succeed())
			})

			locales := filepath.Join(root, "config", "locales")
			Expect(os.MkdirAll(locales, 0o755)).To(Succeed())
			Expect(os.WriteFile(filepath.Join(locales, "en.yml"),
				[]byte("en:\n  who: "+name+"\n"), 0o644)).To(Succeed())
			Expect(os.WriteFile(filepath.Join(root, "entry.js"),
				[]byte("import locales from \"proscenium/i18n\";\nconsole.log(locales);\n"), 0o644)).To(Succeed())
			Expect(os.Chtimes(locales, stamp, stamp)).To(Succeed())

			return root
		}

		for name, root := range map[string]string{"alpha": rootFor("alpha"), "beta": rootFor("beta")} {
			cfg := &types.ConfigT{
				RootPath:        root,
				OutputDir:       "public/assets",
				Environment:     types.TestEnv,
				InternalTesting: true,
				CodeSplitting:   true,
				Bundle:          true,
			}

			success, code, _ := b.BuildToString("entry.js", cfg)
			Expect(success).To(BeTrue())
			Expect(code).To(ContainSubstring(`who: "`+name+`"`), "root %q served another root's locales", name)
		}
	})
})

func BenchmarkI18n(bm *testing.B) {
	cfg := newTestConfig()

	for bm.Loop() {
		success, result, _ := b.BuildToString("lib/i18n/benchmark/index.js", cfg)

		if !success {
			panic("Build failed: " + result)
		}
	}
}
