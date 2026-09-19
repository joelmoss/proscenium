package proscenium_test

import (
	"encoding/json"
	"errors"
	"strings"

	b "joelmoss/proscenium/internal/builder"
	r "joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/utils"

	esbuild "github.com/joelmoss/esbuild-internal/api"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// This library is loaded into a Ruby process over FFI, and an unrecovered panic on the goroutine
// Ruby called into takes that process down. Every spec below that passes a nil config aborted the
// whole test binary before the entry function it calls wrapped itself in utils.Recover: the first
// line of each dereferences cfg. That is the injection point, and it is why these are red-capable
// without a test hook in production code.
var _ = Describe("panic handling", func() {
	Describe("utils.Recover", func() {
		It("returns nil when nothing panics", func() {
			Expect(utils.Recover(func() {})).To(Succeed())
		})

		It("turns a panic into an error carrying the value and the stack", func() {
			err := utils.Recover(func() { panic("boom") })

			Expect(err).To(HaveOccurred())
			Expect(err.Error()).To(HavePrefix("panic: boom\n"))
			Expect(err.Error()).To(ContainSubstring("panic_test.go"))
		})

		It("keeps an error value's message", func() {
			err := utils.Recover(func() { panic(errors.New("wrapped")) })

			Expect(err.Error()).To(HavePrefix("panic: wrapped\n"))
		})
	})

	// The esbuild fork writes every panic it recovers in a plugin callback with this prefix, and it
	// is the one way to tell a panic from an ordinary resolve failure.
	Describe("utils.IsPanicMessage", func() {
		It("recognises the fork's recovered panics", func() {
			Expect(utils.IsPanicMessage(esbuild.Message{Text: "panic: boom (in OnLoad callback)"})).To(BeTrue())
			Expect(utils.IsPanicMessage(esbuild.Message{Text: `Could not resolve "x"`})).To(BeFalse())
			Expect(utils.IsPanicMessage(esbuild.Message{Text: "a panic: in the middle"})).To(BeFalse())
		})

		It("finds one among ordinary messages", func() {
			msgs := []esbuild.Message{{Text: `Could not resolve "x"`}, {Text: "panic: boom (in OnResolve callback)"}}

			Expect(utils.HasPanicMessage(msgs)).To(BeTrue())
			Expect(utils.HasPanicMessage(msgs[:1])).To(BeFalse())
			Expect(utils.HasPanicMessage(nil)).To(BeFalse())
		})
	})

	Describe("BuildToString", func() {
		It("returns a panic as a failed build", func() {
			success, result, hash := b.BuildToString("lib/foo.js", nil)

			Expect(success).To(BeFalse())
			Expect(hash).To(BeEmpty())

			var message esbuild.Message
			Expect(json.Unmarshal([]byte(result), &message)).To(Succeed())
			Expect(message.Text).To(HavePrefix("panic: runtime error: invalid memory address"))
			Expect(message.Text).To(ContainSubstring("build_to_string.go"))
		})
	})

	Describe("Resolve", func() {
		It("returns a panic as the error", func() {
			urlPath, absPath, err := r.Resolve("pkg", "", nil)

			Expect(urlPath).To(BeEmpty())
			Expect(absPath).To(BeEmpty())
			Expect(err).To(HaveOccurred())
			Expect(err.Error()).To(HavePrefix("panic: runtime error: invalid memory address"))
			Expect(err.Error()).To(ContainSubstring("resolve.go"))
		})
	})

	Describe("Compile", func() {
		It("returns a panic as a failed compile", func() {
			success, messages := b.Compile(nil)

			Expect(success).To(BeFalse())

			var result struct{ Errors []esbuild.Message }
			Expect(json.Unmarshal([]byte(messages), &result)).To(Succeed())
			Expect(result.Errors).To(HaveLen(1))
			Expect(result.Errors[0].Text).To(Equal("Build panicked"))

			detail, _ := result.Errors[0].Detail.(string)
			Expect(strings.HasPrefix(detail, "panic: runtime error: invalid memory address")).To(BeTrue(), detail)
			Expect(detail).To(ContainSubstring("compile.go"))
		})
	})
})
