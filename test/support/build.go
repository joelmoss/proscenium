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
	Debug     bool
}

func Build(pathToBuild string, rest ...BuildOpts) esbuild.BuildResult {
	_, filename, _, _ := runtime.Caller(1)

	// Ensure test environment.
	types.Env = types.Environment(2)

	restOpts := BuildOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}

	options := builder.BuildOptions{
		Path:    pathToBuild,
		Root:    path.Join(path.Dir(filename), "internal"),
		BaseUrl: "https://proscenium.test",
		Debug:   restOpts.Debug,
	}

	if restOpts.EnvVars == "" {
		options.EnvVars = "{\"RAILS_ENV\":\"test\"}"
	}

	if restOpts.ImportMap != "" {
		options.ImportMap = []byte(restOpts.ImportMap)
	}

	return builder.Build(options)
}
