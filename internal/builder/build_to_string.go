package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/utils"
	"path"
	"strings"
)

func BuildToString(filePath string) (bool, string) {
	result := Build(filePath, OutputToString)

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
