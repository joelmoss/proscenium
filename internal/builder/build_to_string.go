package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/utils"
	"path"
	"strings"
)

func BuildToString(options BuildOptions) (bool, string) {
	entrypoints := strings.Split(options.Path, ";")
	hasMultipleEntrypoints := len(entrypoints) > 1

	result := Build(options)

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return false, string(err.Error())
		}

		return false, string(j)
	}

	// Multiple paths were given, so return a mapping of inputs to outputs.
	//
	// Example:
	// 	 lib/code_splitting/son.js::public/assets/lib/code_splitting/son$LAGMAD6O$.js;
	// 	 lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$7JJ2HGHC$.js
	if hasMultipleEntrypoints {
		mapping := map[string]string{}
		for _, ep := range entrypoints {
			mapping[ep] = ""
		}

		var meta interface{}
		err := json.Unmarshal([]byte(result.Metafile), &meta)
		if err != nil {
			return false, string(err.Error())
		}

		m := meta.(map[string]interface{})
		for output, v := range m["outputs"].(map[string]interface{}) {
			for k, input := range v.(map[string]interface{}) {
				if k == "entryPoint" {
					mapping[input.(string)] = output
				}
			}
		}

		contents := []string{}
		for _, ep := range entrypoints {
			contents = append(contents, ep+"::"+mapping[ep])
		}

		return true, strings.Join(contents, ";")
	}

	contents := string(result.OutputFiles[0].Contents)

	isSourceMap := strings.HasSuffix(options.Path, ".map")
	if isSourceMap {
		return true, contents
	}

	if utils.IsEncodedUrl(options.Path) {
		contents += "//# sourceMappingURL=" + options.Path + ".map"
	} else {
		sourcemapUrl := path.Base(options.Path)
		if utils.PathIsCss(result.OutputFiles[0].Path) {
			contents += "/*# sourceMappingURL=" + sourcemapUrl + ".map */"
		} else {
			contents += "//# sourceMappingURL=" + sourcemapUrl + ".map"
		}
	}

	return true, contents
}
