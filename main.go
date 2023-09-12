package main

/*
struct Result {
	int success;
	char* response;
};
*/
import "C"

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
)

// Build the given `path` in the `root`.
//
//	BuildOptions
//	- path - The path to build relative to `root`. Multiple paths can be given by separating them
//	  with a semi-colon.
//	- baseUrl - base URL of the Rails app. eg. https://example.com
//	- importMap - Path to the import map relative to `root`.
//	- envVars - JSON string of environment variables.
//	Config:
//	- root - The working directory.
//	- env - The environment (1 = development, 2 = test, 3 = production)
//	- codeSpitting?
//	- debug?
//
//export build
func build(
	filepath *C.char,
	baseUrl *C.char,
	importMap *C.char,
	envVars *C.char,
	appRoot *C.char,
	gemPath *C.char,
	env C.uint,
	codeSplitting bool,
	debug bool,
) C.struct_Result {
	types.Config.RootPath = C.GoString(appRoot)
	types.Config.GemPath = C.GoString(gemPath)
	types.Config.Environment = types.Environment(env)
	types.Config.CodeSplitting = codeSplitting
	types.Config.Debug = debug

	pathStr := C.GoString(filepath)

	success, result := builder.BuildToString(builder.BuildOptions{
		Path:          pathStr,
		BaseUrl:       C.GoString(baseUrl),
		ImportMapPath: C.GoString(importMap),
		EnvVars:       C.GoString(envVars),
	})

	if success {
		return C.struct_Result{C.int(1), C.CString(result)}
	} else {
		return C.struct_Result{C.int(0), C.CString(result)}
	}
}

// Resolve the given `path` relative to the `root`.
//
//	ResolveOptions
//	- path - The path to build relative to `root`.
//	- importMap - Path to the import map relative to `root`.
//	Config
//	- root - The working directory.
//	- env - The environment (1 = development, 2 = test, 3 = production)
//	- debug?
//
//export resolve
func resolve(
	path *C.char, importMap *C.char, appRoot *C.char, gemPath *C.char, env C.uint, debug bool,
) C.struct_Result {
	types.Config.Environment = types.Environment(env)
	types.Config.RootPath = C.GoString(appRoot)
	types.Config.GemPath = C.GoString(gemPath)
	types.Config.Debug = debug

	resolvedPath, err := resolver.Resolve(resolver.Options{
		Path:          C.GoString(path),
		ImportMapPath: C.GoString(importMap),
	})
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(string(err.Error()))}
	}

	return C.struct_Result{C.int(1), C.CString(resolvedPath)}
}

func main() {}
