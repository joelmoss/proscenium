package support

import (
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"path"
	"runtime"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type BuildOpts struct {
	ImportMap string
	EnvVars   string
}

func Build(pathToBuild string, rest ...BuildOpts) esbuild.BuildResult {
	_, filename, _, _ := runtime.Caller(1)

	// Ensure test environment.
	types.Config.Environment = types.Environment(2)
	types.Config.RootPath = path.Join(path.Dir(filename), "dummy")

	restOpts := BuildOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}

	options := builder.BuildOptions{
		Path:    pathToBuild,
		BaseUrl: "https://proscenium.test",
	}

	if restOpts.EnvVars == "" {
		options.EnvVars = "{\"RAILS_ENV\":\"test\"}"
	}

	if restOpts.ImportMap != "" {
		options.ImportMap = []byte(restOpts.ImportMap)
	}

	return builder.Build(options)
}
