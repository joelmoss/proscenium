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

	"github.com/evanw/esbuild/pkg/api"
)

type environment uint8

const (
	devEnv environment = iota + 1
	testEnv
	prodEnv
)

func (e environment) String() string {
	return [...]string{"development", "test", "production"}[e-1]
}

// Build the given `path` in the `root`.
//
//		path - The path to build relative to `root`.
//		root - The working directory.
//	 env  - The environment (1 = development, 2 = test, 3 = production)
//
//export build
func build(path *C.char, root *C.char, env environment, debug bool) C.struct_BuildResult {
	entryPoint := C.GoString(path)
	absWorkingDir := C.GoString(root)
	minify := !debug && env != testEnv

	result := api.Build(api.BuildOptions{
		EntryPoints:       []string{entryPoint},
		AbsWorkingDir:     absWorkingDir,
		LogLevel:          api.LogLevelSilent,
		LogLimit:          1,
		Outdir:            "public/assets",
		Outbase:           "./",
		Format:            api.FormatESModule,
		JSX:               api.JSXAutomatic,
		JSXDev:            env != testEnv && env != prodEnv,
		MinifyWhitespace:  minify,
		MinifyIdentifiers: minify,
		MinifySyntax:      minify,
		Define:            map[string]string{"process.env.NODE_ENV": fmt.Sprintf("'%s'", env)},
		Bundle:            true,
		External:          []string{"*.rjs", "*.gif", "*.jpg", "*.png", "*.woff2", "*.woff"},
		KeepNames:         env != prodEnv,
		Write:             false,
		// Sourcemap: isSourceMap ? 'external' : false,

		// Plugins:     []api.Plugin{envPlugin},

		// The Esbuild default places browser before module, but we're building for modern browsers
		// which support esm. So we prioritise that. Some libraries export a "browser" build that still
		// uses CJS.
		MainFields: []string{"module", "browser", "main"},
	})

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			fmt.Println(err)
			return C.struct_BuildResult{0, C.CString(string(err.Error()))}
		}

		return C.struct_BuildResult{0, C.CString(string(j))}
	}

	outputString := string(result.OutputFiles[0].Contents)
	return C.struct_BuildResult{1, C.CString(outputString)}
}

func main() {
	// fmt.Printf("%s", build("input.ts"))
}
