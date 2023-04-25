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

// Build the given `path` in the `root`.
//
//   - path - The path to build relative to `root`.
//   - root - The working directory.
//   - env - The environment (1 = development, 2 = test, 3 = production)
//   - importMap - Path to the import map relative to `root`.
//   - debug
//
//export build
func build(path *C.char, root *C.char, env C.uint, importMap *C.char, debug bool) C.struct_Result {
	result := builder.Build(builder.BuildOptions{
		Path:          C.GoString(path),
		Root:          C.GoString(root),
		Env:           types.Environment(env),
		ImportMapPath: C.GoString(importMap),
		Debug:         debug,
	})

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return C.struct_Result{C.int(0), C.CString(string(err.Error()))}
		}

		return C.struct_Result{C.int(0), C.CString(string(j))}
	}

	contents := string(result.OutputFiles[0].Contents)

	return C.struct_Result{C.int(1), C.CString(contents)}
}

// Resolve the given `path` in the `root`.
//
//   - path - The path to build relative to `root`.
//   - root - The working directory.
//   - env - The environment (1 = development, 2 = test, 3 = production)
//   - importMap - Path to the import map relative to `root`.
//
//export resolve
func resolve(path *C.char, root *C.char, env C.uint, importMap *C.char) C.struct_Result {
	result, err := resolver.Resolve(resolver.Options{
		Path:          C.GoString(path),
		Root:          C.GoString(root),
		Env:           types.Environment(env),
		ImportMapPath: C.GoString(importMap),
	})
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(string(err.Error()))}
	}

	return C.struct_Result{C.int(1), C.CString(result)}
}

func main() {
	// fmt.Printf("%s", build("input.ts"))
}
