package support

import (
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/types"
	"path"
	"runtime"
)

type ResolveOpts struct {
	Importer  string
	ImportMap string
	Debug     bool
}

func Resolve(pathToResolve string, rest ...ResolveOpts) (string, error) {
	_, filename, _, _ := runtime.Caller(1)

	// Ensure test environment.
	types.Config.Environment = types.Environment(2)
	types.Config.RootPath = path.Join(path.Dir(filename), "..", "fixtures", "dummy")

	restOpts := ResolveOpts{}
	if len(rest) > 0 {
		restOpts = rest[0]
	}

	types.Config.Debug = restOpts.Debug

	options := resolver.Options{
		Path: pathToResolve,
	}
	if restOpts.ImportMap != "" {
		options.ImportMap = []byte(restOpts.ImportMap)
	}
	if restOpts.Importer != "" {
		options.Importer = restOpts.Importer
	}

	return resolver.Resolve(options)
}
