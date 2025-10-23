package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path"
	"regexp"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
)

var entrypointRegex = regexp.MustCompile(`(?i)(.+)\-\$[a-z0-9]+\$(\.[a-z]+(?:\.map)?)$`)

// Builds the given `filePath`, which should be a full URL path, but without the leading slash, and
// returns the contents as a string.
//
// Only used by the Esbuild middleware, so requires `filePath` argument to be an absolute URL path.
// See Proscenium::Middleware::Esbuild.
func BuildToString(filePath string, cacheQueryString ...string) (success bool, code string, contentHash string) {
	var pathPrefix = types.Config.RootPath + "/" + types.Config.OutputDir + "/"
	var output esbuild.OutputFile

	var queryString string
	if len(cacheQueryString) > 0 {
		queryString = cacheQueryString[0]
	}

	result := build(filePath, queryString)

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return false, string(err.Error()), ""
		}

		return false, string(j), ""
	}

	nonSourceMapFile, isSourceMap := strings.CutSuffix(filePath, ".map")

	if len(result.OutputFiles) == 1 {
		output = result.OutputFiles[0]
	} else {
		for _, out := range result.OutputFiles {
			substrs := entrypointRegex.FindAllStringSubmatch(out.Path, -1)[0]
			if pathPrefix+filePath == substrs[1]+substrs[2] {
				output = out
				break
			}
		}

		if output.Path == "" {
			var metadata struct{ Outputs map[string]any }
			err := json.Unmarshal([]byte(result.Metafile), &metadata)
			if err != nil {
				return false, err.Error(), ""
			}

			var epPath string
			if isSourceMap {
				epPath = findOutputPathForEntryPoint(nonSourceMapFile, metadata) + ".map"
			} else {
				epPath = findOutputPathForEntryPoint(filePath, metadata)
			}

			epPath = path.Join(types.Config.RootPath, epPath)

			for _, out := range result.OutputFiles {
				if out.Path == epPath {
					output = out
					break
				}
			}
		}
	}

	// debug.FDebug(filePath, result.OutputFiles, output.Path)

	contents := string(output.Contents)

	if isSourceMap {
		return true, contents, output.Hash
	}

	sourcemapUrl := path.Base(filePath)
	if utils.PathIsCss(output.Path) {
		contents += "/*# sourceMappingURL=" + sourcemapUrl + ".map */"
	} else {
		contents += "//# sourceMappingURL=" + sourcemapUrl + ".map"
	}

	return true, contents, output.Hash
}

func findOutputPathForEntryPoint(filePath string, metadata struct{ Outputs map[string]any }) string {
	for outputPath, details := range metadata.Outputs {
		if entryPoint, ok := details.(map[string]any)["entryPoint"]; ok {
			if entryPointStr, isString := entryPoint.(string); isString {
				if filePath == entryPointStr {
					return outputPath
				}
			}
		}
	}

	return ""
}
