package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/utils"
	"path"
	"strings"
)

func BuildToString(options BuildOptions) (bool, string) {
	options.Output = OutputToString
	result := Build(options)

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return false, string(err.Error())
		}

		return false, string(j)
	}

	contents := string(result.OutputFiles[0].Contents)

	isSourceMap := strings.HasSuffix(options.Path, ".map")
	if isSourceMap {
		return true, contents
	}

	sourcemapUrl := path.Base(options.Path)
	if utils.PathIsCss(result.OutputFiles[0].Path) {
		contents += "/*# sourceMappingURL=" + sourcemapUrl + ".map */"
	} else {
		contents += "//# sourceMappingURL=" + sourcemapUrl + ".map"
	}

	return true, contents
}
