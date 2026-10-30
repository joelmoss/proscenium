package main

/*
#include <stdlib.h>

struct Result {
	int success;
	char* response;
	char* contentHash;
	};
struct ResolveResult {
	int success;
	char* urlPath;
	char* absPath;
};
struct CompileResult {
	int success;
	char* messages;
};
*/
import "C"

import (
	"runtime"
	"sync"
	"time"
	"unsafe"

	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
)

// How long the library must go unused before it gives back its idle threads. Long enough that a
// page's burst of asset requests reuses the threads the first one started.
const threadReleaseDelay = 5 * time.Second

var (
	callsMu      sync.Mutex
	callsRunning int
	releaseTimer *time.Timer
)

func callStarted() {
	callsMu.Lock()
	defer callsMu.Unlock()

	callsRunning++
}

func callFinished() {
	callsMu.Lock()
	defer callsMu.Unlock()

	callsRunning--
	if callsRunning > 0 {
		return
	}

	if releaseTimer == nil {
		releaseTimer = time.AfterFunc(threadReleaseDelay, releaseIdleThreads)
	} else {
		releaseTimer.Reset(threadReleaseDelay)
	}
}

// Go never ends a thread it has started, so each process that has used this library keeps about
// GOMAXPROCS idle threads for life, which on a large box exhausts a container's task limit across
// Puma's workers (#182). The one way to end a thread is documented on runtime.LockOSThread: a
// goroutine that exits while locked takes its thread with it. A parked locked goroutine holds its
// thread, so one for each thread the runtime has claims them all, then all exit together.
//
// Holds callsMu throughout, so a call arriving now waits the few milliseconds this takes rather
// than running alongside it.
//
// shortcut: Go's forced collection every two minutes brings back a few threads with no call to
// release them (measured +7 at GOMAXPROCS 48, then stable), re-arm the timer if that ever matters.
func releaseIdleThreads() {
	callsMu.Lock()
	defer callsMu.Unlock()

	if callsRunning > 0 {
		return
	}

	threads, _ := runtime.ThreadCreateProfile(nil)

	var claimed, exited sync.WaitGroup
	release := make(chan struct{})

	for range threads {
		claimed.Add(1)
		exited.Go(func() {
			runtime.LockOSThread()
			claimed.Done()
			<-release
		})
	}

	claimed.Wait()
	close(release)
	exited.Wait()
}

// Parses the given config JSON into a fresh, independent *types.ConfigT - no caching, no shared
// state. Each call gets its own copy, so concurrent build_to_string/resolve/compile calls (Ruby
// releases the GVL for these - see builder.rb's `blocking: true`) share no configuration and need
// no lock for it. Measured at ~38us for a realistic 60-gem config, a few percent of a single
// build - paid independently per concurrent call, not serialised, so it doesn't cost real
// parallelism.
//
// Config is not the only shared thing, though: the i18n and svg plugins each memoise per app root
// (internal/plugin/i18n.go, svg.go) and carry their own mutex for it. Anything else added here
// that outlives a single call needs the same treatment - keyed by root, because one process
// builds several apps.
func parseConfig(configJson *C.char) (*types.ConfigT, error) {
	return types.NewConfig([]byte(C.GoString(configJson)))
}

// Does nothing, and is kept for that. It is the one export that needs no Rails app and no
// arguments, so bin/verify-installed-gem and test/packaging_test.rb call it to prove the library
// loads and the Go runtime starts, and benchmarks/bridge.rb times it as the bare cost of an FFI
// call. It once reset a global config, which no longer exists: every call parses its own.
//
//export reset_config
func reset_config() {}

// Free a C string previously returned to the Ruby FFI caller via build_to_string, resolve, or
// compile. The Go runtime cannot see or collect memory allocated with C.CString - callers must
// free it explicitly once they're done reading it.
//
//export free_cstr
func free_cstr(ptr *C.char) {
	C.free(unsafe.Pointer(ptr))
}

// Build the given `path` using the `config`.
//
// - path - The path to build relative to `root`.
// - config
//
//export build_to_string
func build_to_string(filePath *C.char, configJson *C.char) C.struct_Result {
	callStarted()
	defer callFinished()

	cfg, err := parseConfig(configJson)
	if err != nil {
		// Ruby parses the response as an esbuild message, so the config error has to be one too.
		return C.struct_Result{C.int(0), C.CString(builder.BuildErrorJSON("Invalid config - " + err.Error())), C.CString("")}
	}

	success, result, contentHash := builder.BuildToString(C.GoString(filePath), cfg)

	if success {
		return C.struct_Result{C.int(1), C.CString(result), C.CString(contentHash)}
	}

	return C.struct_Result{C.int(0), C.CString(result), C.CString("")}
}

// Resolve the given `path` relative to the `root`.
//
// - path - The path to build relative to `root`.
// - config
//
//export resolve
func resolve(filePath *C.char, configJson *C.char) C.struct_ResolveResult {
	callStarted()
	defer callFinished()

	cfg, err := parseConfig(configJson)
	if err != nil {
		return C.struct_ResolveResult{C.int(0), C.CString(err.Error()), C.CString("")}
	}

	urlPath, absPath, err := resolver.Resolve(C.GoString(filePath), "", cfg)
	if err != nil {
		return C.struct_ResolveResult{C.int(0), C.CString(string(err.Error())), C.CString("")}
	}

	return C.struct_ResolveResult{C.int(1), C.CString(urlPath), C.CString(absPath)}
}

// Compile assets using the given `config`.
//
// - config
//
//export compile
func compile(configJson *C.char) C.struct_CompileResult {
	callStarted()
	defer callFinished()

	cfg, err := parseConfig(configJson)
	if err != nil {
		// Ruby parses the response as esbuild's messages, so the config error has to be one too.
		// This used to hand back "", which threw the reason away.
		return C.struct_CompileResult{C.int(0), C.CString(builder.CompileErrorJSON("Invalid config", err.Error()))}
	}

	success, messages := builder.Compile(cfg)

	if success {
		return C.struct_CompileResult{C.int(1), C.CString(messages)}
	}

	return C.struct_CompileResult{C.int(0), C.CString(messages)}
}

func main() {}
