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
	"sync"
	"unsafe"

	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
)

// build_to_string, resolve, compile and reset_config are attached on the Ruby side with
// `blocking: true`, so that a slow build doesn't hold the GVL and stall unrelated Ruby threads.
// That means Ruby can now call into this library from more than one OS thread at once, which
// this global mutex serialises: types.Config, lastConfigJSON, and the builder package's env var
// cache are all unsynchronised globals, so genuinely concurrent calls would race.
var callMutex sync.Mutex

// Cache the last config JSON to skip unmarshalling when unchanged.
var lastConfigJSON string

func unmarshalConfigIfChanged(configJson *C.char) error {
	json := C.GoString(configJson)
	if json == lastConfigJSON {
		return nil
	}

	err := types.UnmarshalConfig([]byte(json))
	if err != nil {
		return err
	}

	lastConfigJSON = json
	return nil
}

//export reset_config
func reset_config() {
	callMutex.Lock()
	defer callMutex.Unlock()

	types.Config.Reset()
	lastConfigJSON = ""
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
	callMutex.Lock()
	defer callMutex.Unlock()

	err := unmarshalConfigIfChanged(configJson)
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(err.Error()), C.CString("")}
	}

	success, result, contentHash := builder.BuildToString(C.GoString(filePath), &types.Config)

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
	callMutex.Lock()
	defer callMutex.Unlock()

	err := unmarshalConfigIfChanged(configJson)
	if err != nil {
		return C.struct_ResolveResult{C.int(0), C.CString(err.Error()), C.CString("")}
	}

	urlPath, absPath, err := resolver.Resolve(C.GoString(filePath), "", &types.Config)
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
	callMutex.Lock()
	defer callMutex.Unlock()

	err := unmarshalConfigIfChanged(configJson)
	if err != nil {
		return C.struct_CompileResult{C.int(0), C.CString("")}
	}

	success, messages := builder.Compile(&types.Config)

	if success {
		return C.struct_CompileResult{C.int(1), C.CString(messages)}
	}

	return C.struct_CompileResult{C.int(0), C.CString(messages)}
}

func main() {}
