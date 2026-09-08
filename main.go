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
	"unsafe"

	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
)

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

//export reset_config
func reset_config() {
	types.Config.Reset()
}

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
	cfg, err := parseConfig(configJson)
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(err.Error()), C.CString("")}
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
	cfg, err := parseConfig(configJson)
	if err != nil {
		return C.struct_CompileResult{C.int(0), C.CString("")}
	}

	success, messages := builder.Compile(cfg)

	if success {
		return C.struct_CompileResult{C.int(1), C.CString(messages)}
	}

	return C.struct_CompileResult{C.int(0), C.CString(messages)}
}

func main() {}
