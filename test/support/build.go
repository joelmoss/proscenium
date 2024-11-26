package support

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/types"
	"path"
	"runtime"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type BuildOpts struct {
	ImportMap     string
	ImportMapPath string
	EnvVars       string
	Engines       map[string]string
	Debug         bool
}

func BuildToString(pathToBuild string, rest ...BuildOpts) (bool, string) {
	_, filename, _, _ := runtime.Caller(1)
	types.Config.RootPath = path.Join(path.Dir(filename), "..", "fixtures", "dummy")

	restOpts := BuildOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}
	buildConfig(restOpts)

	return builder.BuildToString(pathToBuild)
}

func BuildToPath(pathToBuild string, rest ...BuildOpts) (bool, string) {
	_, filename, _, _ := runtime.Caller(1)
	types.Config.RootPath = path.Join(path.Dir(filename), "..", "fixtures", "dummy")

	restOpts := BuildOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}
	buildConfig(restOpts)

	return builder.BuildToPath(pathToBuild)
}

func Build(pathToBuild string, rest ...BuildOpts) esbuild.BuildResult {
	_, filename, _, _ := runtime.Caller(1)
	types.Config.RootPath = path.Join(path.Dir(filename), "..", "fixtures", "dummy")

	restOpts := BuildOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}
	buildConfig(restOpts)

	return builder.Build(pathToBuild, builder.OutputToString)
}

func buildConfig(restOpts BuildOpts) {
	// Ensure test environment.
	types.Config.Environment = types.Environment(2)

	types.Config.Debug = restOpts.Debug
	types.Config.Engines = restOpts.Engines

	_, filename, _, _ := runtime.Caller(1)
	types.Config.GemPath = path.Join(path.Dir(filename), "..", "..")

	// if restOpts.EnvVars == "" {
	// 	types.Config.EnvVars = make(map[string]string)
	// 	types.Config.EnvVars["NODE_ENV"] = "test"
	// }

	if restOpts.ImportMap != "" {
		importmap.Contents.IsParsed = false
		importmap.Parse([]byte(restOpts.ImportMap))
	} else if restOpts.ImportMapPath != "" {
		types.Config.ImportMapPath = restOpts.ImportMapPath
	}
}
