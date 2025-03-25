package main

/*
struct Result {
	int success;
	char* response;
};
*/
import "C"

import (
	"encoding/json"
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
)

//export reset_config
func reset_config() {
	types.Config.Reset()
}

// Build the given `path` using the `config`.
//
// - path - The path to build relative to `root`.
// - config
//
//export build_to_string
func build_to_string(filePath *C.char, configJson *C.char) C.struct_Result {
	err := json.Unmarshal([]byte(C.GoString(configJson)), &types.Config)
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(err.Error())}
	}

	success, result := builder.BuildToString(C.GoString(filePath))

	if success {
		return C.struct_Result{C.int(1), C.CString(result)}
	}

	return C.struct_Result{C.int(0), C.CString(result)}
}

// Resolve the given `path` relative to the `root`.
//
// - path - The path to build relative to `root`.
// - config
//
//export resolve
func resolve(filePath *C.char, configJson *C.char) C.struct_Result {
	err := json.Unmarshal([]byte(C.GoString(configJson)), &types.Config)
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(err.Error())}
	}

	resolvedPath, err := resolver.Resolve(C.GoString(filePath), "")
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(string(err.Error()))}
	}

	return C.struct_Result{C.int(1), C.CString(resolvedPath)}
}

func main() {}
