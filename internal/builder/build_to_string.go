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
// Only used by the Esbuild middleware. See Proscenium::Middleware::Esbuild.
func BuildToString(filePath string) (success bool, code string) {
	result := build(filePath, false)

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return false, string(err.Error())
		}

		return false, string(j)
	}

	contents := string(result.OutputFiles[0].Contents)

	isSourceMap := strings.HasSuffix(filePath, ".map")
	if isSourceMap {
		return true, contents
	}

	sourcemapUrl := path.Base(filePath)
	if utils.PathIsCss(result.OutputFiles[0].Path) {
		contents += "/*# sourceMappingURL=" + sourcemapUrl + ".map */"
	} else {
		contents += "//# sourceMappingURL=" + sourcemapUrl + ".map"
	}

	return true, contents
}
