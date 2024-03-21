package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/types"
	"path/filepath"
	"strings"
)

var libsSplitPath = "/proscenium/libs/"

// Return a mapping of path inputs to outputs.
//
// Output example:
//
//	lib/code_splitting/son.js::public/assets/lib/code_splitting/son$LAGMAD6O$.js;
//	lib/code_splitting/daughter.js::public/assets/lib/code_splitting/daughter$7JJ2HGHC$.js
func BuildToPath(options BuildOptions) (bool, string) {
	entrypoints := strings.Split(options.Path, ";")
	options.Output = OutputToPath

	result := Build(options)

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return false, string(err.Error())
		}

		return false, string(j)
	}

	// Paths which are not a descendent of the root will be returned as a relative path. For
	// example: `gem4/lib/gem4/gem4.js` will be returned as `../external/gem4/lib/gem4/gem4.js`. And
	// that means the returned mapping will be incorrect, as the keys of the map are the original
	// entrypoints. They need to match the returned paths.
	mapping := map[string]string{}
	for _, ep := range entrypoints {
		relPath := entryPointToRelativePath(ep)
		if relPath == ep {
			mapping[ep] = ""
		} else {
			mapping[entryPointToRelativePath(ep)] = ep
		}
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
				key := input.(string)
				if strings.Contains(key, libsSplitPath) {
					sliced := strings.Split(key, libsSplitPath)
					key = "@proscenium/" + sliced[len(sliced)-1]
				}

				if mapping[key] == "" {
					mapping[key] = output
				} else {
					mapping[mapping[key]] = output
					delete(mapping, key)
				}
			}
		}
	}

	contents := []string{}
	for _, ep := range entrypoints {
		contents = append(contents, ep+"::"+mapping[ep])
	}

	return true, strings.Join(contents, ";")

}

func entryPointToRelativePath(entryPoint string) string {
	relPath := ""

	for key, value := range types.Config.Engines {
		prefix := key + "/"
		if strings.HasPrefix(entryPoint, prefix) {
			newPath := filepath.Join(value, strings.TrimPrefix(entryPoint, prefix))
			relPath, _ = filepath.Rel(types.Config.RootPath, newPath)
			break
		}
	}

	if relPath != "" {
		return relPath
	} else {
		return entryPoint
	}
}
