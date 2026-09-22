package proscenium_test

import (
	"joelmoss/proscenium/internal/utils"
	"runtime"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// The two absoluteness predicates, which exist because one predicate cannot answer both
// questions. See the doc comment above them in internal/utils/utils.go.
//
// These run on every platform, and they are the only part of the Windows path work that does:
// filepath.ToSlash is the identity on Unix, so nothing else here is observable locally.
var _ = Describe("path spaces", func() {
	Describe("UrlPathIsAbs", func() {
		It("is true for a path rooted at the app", func() {
			Expect(utils.UrlPathIsAbs("/lib/x.js")).To(BeTrue())
			Expect(utils.UrlPathIsAbs("/")).To(BeTrue())
		})

		It("is false for a Windows filesystem path, which is not a URL", func() {
			Expect(utils.UrlPathIsAbs("C:/app/x.js")).To(BeFalse())
			Expect(utils.UrlPathIsAbs(`C:\app\x.js`)).To(BeFalse())
		})

		It("is false for relative, bare and empty", func() {
			Expect(utils.UrlPathIsAbs("./x.js")).To(BeFalse())
			Expect(utils.UrlPathIsAbs("../x.js")).To(BeFalse())
			Expect(utils.UrlPathIsAbs("pkg/x.js")).To(BeFalse())
			Expect(utils.UrlPathIsAbs("")).To(BeFalse())
		})
	})

	Describe("FsPathIsAbs", func() {
		It("is true for a path from the filesystem root, on every platform", func() {
			Expect(utils.FsPathIsAbs("/Users/j/app/x.js")).To(BeTrue())
			Expect(utils.FsPathIsAbs("//server/share/x.js")).To(BeTrue())
		})

		It("is false for relative, bare and empty", func() {
			Expect(utils.FsPathIsAbs("./x.js")).To(BeFalse())
			Expect(utils.FsPathIsAbs("../x.js")).To(BeFalse())
			Expect(utils.FsPathIsAbs("pkg/x.js")).To(BeFalse())
			Expect(utils.FsPathIsAbs("")).To(BeFalse())
		})

		// A drive letter is a root on Windows and a directory called "C:" on Unix, so this
		// predicate has to answer differently per platform rather than accept both everywhere.
		It("answers for a drive letter according to the platform", func() {
			if runtime.GOOS == "windows" {
				Expect(utils.FsPathIsAbs("C:/app/x.js")).To(BeTrue())
				Expect(utils.FsPathIsAbs(`C:\app\x.js`)).To(BeTrue())
			} else {
				Expect(utils.FsPathIsAbs("C:/app/x.js")).To(BeFalse())
				Expect(utils.FsPathIsAbs(`C:\app\x.js`)).To(BeFalse())
			}
		})

		// "C:" with no separator is relative to that drive's current directory, not its root.
		It("is false for a bare drive letter", func() {
			Expect(utils.FsPathIsAbs("C:")).To(BeFalse())
		})
	})

	Describe("IsBareModule", func() {
		It("is false for a Windows filesystem path", func() {
			if runtime.GOOS == "windows" {
				Expect(utils.IsBareModule("C:/app/x.js")).To(BeFalse())
				Expect(utils.IsBareModule(`C:\app\x.js`)).To(BeFalse())
			} else {
				Expect(utils.IsBareModule("C:/app/x.js")).To(BeTrue())
				Expect(utils.IsBareModule(`C:\app\x.js`)).To(BeTrue())
			}
		})

		It("is unchanged for everything else", func() {
			Expect(utils.IsBareModule("pkg/x.js")).To(BeTrue())
			Expect(utils.IsBareModule("@scope/pkg")).To(BeTrue())
			Expect(utils.IsBareModule("/lib/x.js")).To(BeFalse())
			Expect(utils.IsBareModule("./x.js")).To(BeFalse())
			Expect(utils.IsBareModule("unbundle:pkg")).To(BeFalse())
		})
	})

	Describe("JoinFsPath", func() {
		It("returns slash-form", func() {
			Expect(utils.JoinFsPath("/app", "lib", "x.js")).To(Equal("/app/lib/x.js"))
			Expect(utils.JoinFsPath("/app", "./lib/../x.js")).To(Equal("/app/x.js"))
		})

		// path.Join collapses this to "/server/share/x.js", which names a different machine.
		It("keeps a UNC root, which path.Join destroys", func() {
			if runtime.GOOS != "windows" {
				Skip("UNC roots only mean anything on Windows")
			}

			Expect(utils.JoinFsPath(`\\server\share`, "x.js")).To(Equal("//server/share/x.js"))
		})
	})
})
