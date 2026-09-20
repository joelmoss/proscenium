package utils

import (
	"fmt"
	"runtime/debug"
	"slices"
	"strings"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

// A panic caught by Recover: the value and the goroutine stack at the point of the panic, kept
// apart so each caller can put them where its own failure shape puts a message and a detail.
type PanicError struct {
	Value any
	Stack string
}

// The one-line summary, in the same shape the esbuild fork gives a panic it recovers in a plugin
// callback, so every recovered panic reads "panic: ..." wherever it surfaces.
func (e *PanicError) Text() string {
	return fmt.Sprintf("panic: %v", e.Value)
}

func (e *PanicError) Error() string {
	return e.Text() + "\n" + e.Stack
}

// Runs fn and turns a panic in it into a PanicError, or nil.
//
// This library is loaded into a Ruby process over FFI, and an unrecovered panic on the goroutine
// Ruby called into takes that process down. The entry functions the cgo exports call
// (BuildToString, Resolve, Compile) wrap their bodies in this and return their own failure
// value. It cannot see a panic on another goroutine: esbuild's plugin callbacks run on esbuild's
// own goroutines, and the fork recovers those itself, into a message that IsPanicMessage
// recognises. esbuild's internal goroutines (the linker's) have no recover on either side.
func Recover(fn func()) (perr *PanicError) {
	defer func() {
		if r := recover(); r != nil {
			perr = &PanicError{Value: r, Stack: string(debug.Stack())}
		}
	}()

	fn()

	return nil
}

// Whether the message is a panic the esbuild fork recovered in a plugin callback. The fork writes
// every such message with this prefix (pkg/api/api_impl.go, pluginPanicMsg), and it is the one
// way to tell a panic from an ordinary resolve failure: a plugin that treats every resolve error
// as "not found" would otherwise externalise the import and hide the panic behind a successful
// build. The fork's own tests pin the exact text.
func IsPanicMessage(m esbuild.Message) bool {
	return strings.HasPrefix(m.Text, "panic:")
}

// Whether any of the messages is a recovered panic.
func HasPanicMessage(msgs []esbuild.Message) bool {
	return slices.ContainsFunc(msgs, IsPanicMessage)
}

// Whether the error is a recovered panic: a PanicError from Recover, or a fork-recovered message
// that Resolve turned into an error. For callers that treat every error as an ordinary miss.
func IsPanicError(err error) bool {
	return err != nil && strings.HasPrefix(err.Error(), "panic:")
}

// A message as one string: its text, then each note on a line of its own. For the callers that
// can only hand Ruby a string (Resolve), where a recovered panic's stack would otherwise be lost
// with the note that carries it.
func MessageText(m esbuild.Message) string {
	parts := make([]string, 0, 1+len(m.Notes))
	parts = append(parts, m.Text)
	for _, note := range m.Notes {
		parts = append(parts, note.Text)
	}

	return strings.Join(parts, "\n")
}
