package support

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"path"
	"runtime"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type BuildOpts struct {
	ImportMap     string
	ImportMapPath string
	EnvVars       string
	Debug         bool
}

func BuildToString(pathToBuild string, rest ...BuildOpts) (bool, string) {
	_, filename, _, _ := runtime.Caller(1)
	types.Config.RootPath = path.Join(path.Dir(filename), "dummy")

	restOpts := BuildOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}

	return builder.BuildToString(buildOptions(pathToBuild, restOpts))
}

func Build(pathToBuild string, rest ...BuildOpts) esbuild.BuildResult {
	_, filename, _, _ := runtime.Caller(1)
	types.Config.RootPath = path.Join(path.Dir(filename), "dummy")

	restOpts := BuildOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}

	return builder.Build(buildOptions(pathToBuild, restOpts))
}

func buildOptions(pathToBuild string, restOpts BuildOpts) builder.BuildOptions {
	// Ensure test environment.
	types.Config.Environment = types.Environment(2)

	options := builder.BuildOptions{
		Path:    pathToBuild,
		BaseUrl: "https://proscenium.test",
	}

	types.Config.Debug = restOpts.Debug

	if restOpts.EnvVars == "" {
		options.EnvVars = "{\"RAILS_ENV\":\"test\"}"
	}

	if restOpts.ImportMap != "" {
		options.ImportMap = []byte(restOpts.ImportMap)
	} else if restOpts.ImportMapPath != "" {
		options.ImportMapPath = restOpts.ImportMapPath
	}

	return options
}
