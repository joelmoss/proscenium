package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/utils"
	"path"
	"strings"
)

// Builds the given `filePath`, which should be a full URL path, but without the leading slash, and
// returns the contents as a string.
//
// Only used by the Esbuild middleware, so requires `filePath` argument to be an absolute URL path.
// See Proscenium::Middleware::Esbuild.
func BuildToString(filePath string) (success bool, code string, contentHash string) {
	result := build(filePath)

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return false, string(err.Error()), ""
		}

		return false, string(j), ""
	}

	output := result.OutputFiles[0]

	contents := string(output.Contents)

	isSourceMap := strings.HasSuffix(filePath, ".map")
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
