package testing

import (
	"joelmoss/proscenium/internal/builder"
	"path"
	"runtime"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

type BuildOpts struct {
	ImportMap string
	Bundle    bool
}

func Build(pathToBuild string, rest ...BuildOpts) esbuild.BuildResult {
	_, filename, _, _ := runtime.Caller(1)

	restOpts := BuildOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}

	options := builder.BuildOptions{
		Path:    pathToBuild,
		Root:    path.Join(path.Dir(filename), "../../test/internal"),
		BaseUrl: "https://proscenium.test",
		Bundle:  restOpts.Bundle,
	}

	if restOpts.ImportMap != "" {
		options.ImportMap = []byte(restOpts.ImportMap)
	}

	return builder.Build(options)
}
