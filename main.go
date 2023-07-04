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
	"joelmoss/proscenium/internal/utils"
	"path"
	"strings"
)

// Build the given `path` in the `root`.
//
//   - path - The path to build relative to `root`. Multiple paths can be given by separating them
//     with a semi-colon.
//   - root - The working directory.
//   - baseUrl - base URL of the Rails app. eg. https://example.com
//   - importMap - Path to the import map relative to `root`.
//   - envVars - JSON string of environment variables.
//   - env - The environment (1 = development, 2 = test, 3 = production)
//   - codeSpitting?
//   - debug?
//
//export build
func build(
	filepath *C.char,
	root *C.char,
	baseUrl *C.char,
	importMap *C.char,
	envVars *C.char,
	env C.uint,
	codeSplitting bool,
	debug bool,
) C.struct_Result {
	types.Config.Environment = types.Environment(env)
	types.Config.CodeSplitting = codeSplitting
	types.Config.Debug = debug

	pathStr := C.GoString(filepath)

	result := builder.Build(builder.BuildOptions{
		Path:          pathStr,
		Root:          C.GoString(root),
		BaseUrl:       C.GoString(baseUrl),
		ImportMapPath: C.GoString(importMap),
		EnvVars:       C.GoString(envVars),
	})

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return C.struct_Result{C.int(0), C.CString(string(err.Error()))}
		}

		return C.struct_Result{C.int(0), C.CString(string(j))}
	}

	if strings.Contains(pathStr, ";") {
		contents := []string{}
		for _, v := range result.OutputFiles {
			contents = append(contents, v.Path)
		}

		return C.struct_Result{C.int(1), C.CString(strings.Join(contents, ";"))}
	}

	contents := string(result.OutputFiles[0].Contents)

	isSourceMap := strings.HasSuffix(pathStr, ".map")
	if isSourceMap {
		return C.struct_Result{C.int(1), C.CString(contents)}
	}

	if utils.IsEncodedUrl(pathStr) {
		contents += "//# sourceMappingURL=" + pathStr + ".map"
	} else {
		sourcemapUrl := path.Base(pathStr)
		if utils.PathIsCss(result.OutputFiles[0].Path) {
			contents += "/*# sourceMappingURL=" + sourcemapUrl + ".map */"
		} else {
			contents += "//# sourceMappingURL=" + sourcemapUrl + ".map"
		}
	}

	return C.struct_Result{C.int(1), C.CString(contents)}
}

// Resolve the given `path` relative to the `root`.
//
//   - path - The path to build relative to `root`.
//   - root - The working directory.
//   - env - The environment (1 = development, 2 = test, 3 = production)
//   - importMap - Path to the import map relative to `root`.
//
//export resolve
func resolve(path *C.char, root *C.char, importMap *C.char, env C.uint) C.struct_Result {
	types.Config.Environment = types.Environment(env)

	resolvedPath, err := resolver.Resolve(resolver.Options{
		Path:          C.GoString(path),
		Root:          C.GoString(root),
		ImportMapPath: C.GoString(importMap),
	})
	if err != nil {
		return C.struct_Result{C.int(0), C.CString(string(err.Error()))}
	}

	return C.struct_Result{C.int(1), C.CString(resolvedPath)}
}

func main() {}
