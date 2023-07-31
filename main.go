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
	root *C.char,
	env C.uint,
	codeSplitting bool,
	debug bool,
) C.struct_Result {
	types.Config.RootPath = C.GoString(root)
	types.Config.Environment = types.Environment(env)
	types.Config.CodeSplitting = codeSplitting
	types.Config.Debug = debug

	pathStr := C.GoString(filepath)

	result := builder.Build(builder.BuildOptions{
		Path:          pathStr,
		BaseUrl:       C.GoString(baseUrl),
		ImportMapPath: C.GoString(importMap),
		EnvVars:       C.GoString(envVars),
		Metafile:      true,
	})

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return C.struct_Result{C.int(0), C.CString(string(err.Error()))}
		}

		return C.struct_Result{C.int(0), C.CString(string(j))}
	}

	// Multiple paths were given, so return a mapping of inputs to outputs as a JSON encoded string.
	if strings.Contains(pathStr, ";") {
		contents := []string{}

		var meta interface{}
		err := json.Unmarshal([]byte(result.Metafile), &meta)
		if err != nil {
			return C.struct_Result{C.int(0), C.CString(string(err.Error()))}
		}

		m := meta.(map[string]interface{})
		for output, v := range m["outputs"].(map[string]interface{}) {
			for k, input := range v.(map[string]interface{}) {
				if k == "entryPoint" {
					contents = append(contents, input.(string)+"::"+output)
				}
			}
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
//	ResolveOptions
//	- path - The path to build relative to `root`.
//	- importMap - Path to the import map relative to `root`.
//	Config
//	- root - The working directory.
//	- env - The environment (1 = development, 2 = test, 3 = production)
//
//export resolve
func resolve(path *C.char, importMap *C.char, root *C.char, env C.uint) C.struct_Result {
	types.Config.Environment = types.Environment(env)
	types.Config.RootPath = C.GoString(root)

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
