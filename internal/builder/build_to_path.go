package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path/filepath"
	"regexp"
	"strings"
)

// Builds the given URL file path to a file located in public/assets, It returns a mapping of the
// path input to its output file path as a string seperated by double colon `::`. The input path can
// also be multiple files each separated by a semicolon.
//
// Each output file is appended with a unique hash to support caching.
//
// Note that this function is only used by side loading and the `compute_asset_path` Rails helper,
// so expects and only supports a full URL path.
//
// Example:
//
//	input: "lib/foo.js"
//	output: "lib/foo.js::public/assets/lib/foo$2IXPSM5U$.js"
//
// or with multiple files:
//
//	input: "son.js;daughter.js"
//	output: "son.js::public/assets/son$LAGMAD6O$.js;daughter.js::public/assets/daughter$7JJ2HGHC$.js"
func BuildToPath(filePath string) (success bool, paths string) {
	result := build(filePath, true)
	entrypoints := strings.Split(filePath, ";")

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return false, string(err.Error())
		}

		return false, string(j)
	}

	// Paths which are not a descendent of the root will be returned as a relative path, which will
	// usually be RubyGems. For example: `gem4/lib/gem4/gem4.js` will be returned as
	// `../external/gem4/lib/gem4/gem4.js`. And that means the returned mapping will be incorrect, as
	// the keys of the map are the original entrypoints. They need to match the returned paths.
	mapping := map[string]string{}
	for _, ep := range entrypoints {
		relPath := entryPointToRelativePath(ep)
		if relPath == ep {
			mapping[ep] = ""
		} else {
			mapping[relPath] = ep
		}
	}

	var meta any
	err := json.Unmarshal([]byte(result.Metafile), &meta)
	if err != nil {
		return false, string(err.Error())
	}

	// Find the output file path for each entrypoint.
	m := meta.(map[string]any)
	for output, v := range m["outputs"].(map[string]any) {
		for k := range v.(map[string]any) {
			if k == "entryPoint" {
				key := stripBuildHash(strings.TrimPrefix(output, "public/assets/"))
				mapping[key] = output
			}
		}
	}

	debug.Debug(meta, entrypoints, mapping)

	contents := []string{}
	for _, ep := range entrypoints {
		contents = append(contents, ep+"::"+mapping[ep])
	}

	return true, strings.Join(contents, ";")
}

func stripBuildHash(path string) string {
	re := regexp.MustCompile(`\$[^$]+\$`)
	return re.ReplaceAllString(path, "")
}

func entryPointToRelativePath(entryPoint string) string {
	relPath := ""

	// Ruby gems must begin with `node_modules/`.
	if utils.IsRubyGem(entryPoint, true) {
		entryPoint = strings.TrimPrefix(entryPoint, "node_modules/")

		gemName, gemPath, err := utils.ResolveRubyGem(entryPoint)
		if err != nil {
			return entryPoint
		}

		// Trim "@rubygems/gemName/" prefix from the entryPoint and append the rest to the gemPath.
		entryPointPath := utils.RemoveRubygemPrefix(entryPoint, gemName)
		newPath := filepath.Join(gemPath, entryPointPath)
		relPath, _ = filepath.Rel(types.Config.RootPath, newPath)
	}

	if relPath != "" {
		return relPath
	} else {
		return entryPoint
	}
}
