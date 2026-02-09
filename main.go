package main

/*
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
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
)

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
	types.Config.Reset()
	lastConfigJSON = ""
}

// Build the given `path` using the `config`.
//
// - path - The path to build relative to `root`.
// - config
//
//export build_to_string
func build_to_string(filePath *C.char, configJson *C.char) C.struct_Result {
	err := unmarshalConfigIfChanged(configJson)
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(err.Error()), C.CString("")}
	}

	success, result, contentHash := builder.BuildToString(C.GoString(filePath))

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
	err := unmarshalConfigIfChanged(configJson)
	if err != nil {
		return C.struct_ResolveResult{C.int(0), C.CString(err.Error()), C.CString("")}
	}

	urlPath, absPath, err := resolver.Resolve(C.GoString(filePath), "")
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
	err := unmarshalConfigIfChanged(configJson)
	if err != nil {
		return C.struct_CompileResult{C.int(0), C.CString("")}
	}

	success, messages := builder.Compile()

	if success {
		return C.struct_CompileResult{C.int(1), C.CString(messages)}
	}

	return C.struct_CompileResult{C.int(0), C.CString(messages)}
}

func main() {}
