package main

/*
struct BuildResult {
	int success;
	char* response;
};
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"joelmoss/proscenium/golib"
	"joelmoss/proscenium/golib/internal"
)

// Build the given `path` in the `root`.
//
//		path - The path to build relative to `root`.
//		root - The working directory.
//		importMap - Path to the import map relative to `root`.
//	 	debug
//
//export build
func build(path *C.char, root *C.char, env C.uint, importMap *C.char, debug bool) C.struct_BuildResult {
	result := golib.Build(golib.BuildOptions{
		Path:          C.GoString(path),
		Root:          C.GoString(root),
		Env:           internal.Environment(env),
		ImportMapPath: C.GoString(importMap),
		Debug:         debug,
	})

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			fmt.Println(err)
			return C.struct_BuildResult{C.int(0), C.CString(string(err.Error()))}
		}

		return C.struct_BuildResult{C.int(0), C.CString(string(j))}
	}

	contents := string(result.OutputFiles[0].Contents)

	return C.struct_BuildResult{C.int(1), C.CString(contents)}
}

func main() {
	// fmt.Printf("%s", build("input.ts"))
}
