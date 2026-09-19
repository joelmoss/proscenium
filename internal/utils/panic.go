package utils

import (
	"fmt"
	"runtime/debug"
	"strings"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

// Runs fn and turns a panic in it into an error carrying the panic value and the stack.
//
// This library is loaded into a Ruby process over FFI, and an unrecovered panic on the goroutine
// Ruby called into takes that process down. The entry functions the cgo exports call
// (BuildToString, Resolve, Compile) wrap their bodies in this and return their own failure
// value. It cannot see a panic on another goroutine - esbuild's plugin callbacks run on esbuild's
// own goroutines, and the fork recovers those itself, into a message that IsPanicMessage
// recognises.
func Recover(fn func()) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic: %v\n%s", r, debug.Stack())
		}
	}()

	fn()

	return nil
}

// Whether the message is a panic the esbuild fork recovered in a plugin callback. The fork writes
// every such message with this prefix (pkg/api/api_impl.go, pluginPanicMsg), and it is the one
// way to tell a panic from an ordinary resolve failure: a plugin that treats every resolve error
// as "not found" would otherwise externalise the import and hide the panic behind a successful
// build.
func IsPanicMessage(m esbuild.Message) bool {
	return strings.HasPrefix(m.Text, "panic:")
}

// Whether any of the messages is a recovered panic.
func HasPanicMessage(msgs []esbuild.Message) bool {
	for _, m := range msgs {
		if IsPanicMessage(m) {
			return true
		}
	}

	return false
}
