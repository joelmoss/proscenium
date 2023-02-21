package main

// go build -buildmode=c-shared -o main.so main.go

import "C"
import "os"
import "strings"
import "encoding/json"

// import "fmt"
import "github.com/evanw/esbuild/pkg/api"

//export transform
func transform(input *C.char) *C.char {
	inputString := C.GoString(input)
	result := api.Transform(inputString, api.TransformOptions{
		Loader: api.LoaderJS,
	})

	s := string(result.Code)

	return C.CString(s)
}

var envPlugin = api.Plugin{
	Name: "env",
	Setup: func(build api.PluginBuild) {
		// Intercept import paths called "env" so esbuild doesn't attempt
		// to map them to a file system location. Tag them with the "env-ns"
		// namespace to reserve them for this plugin.
		build.OnResolve(api.OnResolveOptions{Filter: `^env$`},
			func(args api.OnResolveArgs) (api.OnResolveResult, error) {
				return api.OnResolveResult{
					Path:      args.Path,
					Namespace: "env-ns",
				}, nil
			})

		// Load paths tagged with the "env-ns" namespace and behave as if
		// they point to a JSON file containing the environment variables.
		build.OnLoad(api.OnLoadOptions{Filter: `.*`, Namespace: "env-ns"},
			func(args api.OnLoadArgs) (api.OnLoadResult, error) {
				mappings := make(map[string]string)
				for _, item := range os.Environ() {
					if equals := strings.IndexByte(item, '='); equals != -1 {
						mappings[item[:equals]] = item[equals+1:]
					}
				}
				bytes, err := json.Marshal(mappings)
				if err != nil {
					return api.OnLoadResult{}, err
				}
				contents := string(bytes)
				return api.OnLoadResult{
					Contents: &contents,
					Loader:   api.LoaderJSON,
				}, nil
			})
	},
}

//export build
func build(entrypoint *C.char) *C.char {
	entrypointString := C.GoString(entrypoint)

	result := api.Build(api.BuildOptions{
		EntryPoints: []string{entrypointString},
		Bundle:      true,
		Plugins:     []api.Plugin{envPlugin},
		Write:       false,
	})

	outputString := string(result.OutputFiles[0].Contents)
	return C.CString(outputString)
}

func main() {
	// fmt.Println(transform())
	// fmt.Printf("%s", build("input.ts"))
}
