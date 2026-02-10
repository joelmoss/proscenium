package builder

import (
	"encoding/json"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"path"
	"path/filepath"
	"regexp"
	"strings"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

var entrypointRegex = regexp.MustCompile(`(?i)(.+)\-\$[a-z0-9]+\$(\.[a-z]+(?:\.map)?)$`)
var extensionMap = map[string]string{
	".jsx": ".js",
	".ts":  ".js",
	".tsx": ".js",
	".mjs": ".js",
	".cjs": ".js",
}

// Builds the given `filePath`, which should be a full URL path, but without the leading slash, and
// returns the contents as a string.
//
// Only used by the Esbuild middleware, so requires `filePath` argument to be an absolute URL path.
// See Proscenium::Middleware::Esbuild.
func BuildToString(filePath string) (success bool, code string, contentHash string) {
	var pathPrefix = filepath.Join(types.Config.RootPath, types.Config.OutputDir) + string(filepath.Separator)
	var output esbuild.OutputFile

	result := build(filePath)

	if len(result.Errors) != 0 {
		j, err := json.Marshal(result.Errors[0])
		if err != nil {
			return buildError(string(err.Error()))
		}

		return false, string(j), ""
	}

	nonSourceMapFile, isSourceMap := strings.CutSuffix(filePath, ".map")

	filePathWithRealExt := filePath
	ext := path.Ext(nonSourceMapFile)

	if mappedExt, ok := extensionMap[ext]; ok {
		filePathWithRealExt = strings.TrimSuffix(nonSourceMapFile, ext) + mappedExt

		if isSourceMap {
			filePathWithRealExt = filePathWithRealExt + ".map"
		}
	}

	if len(result.OutputFiles) == 1 {
		output = result.OutputFiles[0]
	} else {
		if len(result.OutputFiles) == 2 {
			if isSourceMap {
				// Get the source map file.
				if strings.HasSuffix(result.OutputFiles[0].Path, ".map") {
					output = result.OutputFiles[0]
				} else if strings.HasSuffix(result.OutputFiles[1].Path, ".map") {
					output = result.OutputFiles[1]
				}
			} else {
				// Get the non-source map file.
				if !strings.HasSuffix(result.OutputFiles[0].Path, ".map") {
					output = result.OutputFiles[0]
				} else if !strings.HasSuffix(result.OutputFiles[1].Path, ".map") {
					output = result.OutputFiles[1]
				}
			}
		}

		if output.Path == "" {
			for _, out := range result.OutputFiles {
				substrs := entrypointRegex.FindAllStringSubmatch(out.Path, -1)[0]
				if pathPrefix+filePathWithRealExt == substrs[1]+substrs[2] {
					output = out
					break
				}
			}
		}

		if output.Path == "" {
			var metadata struct{ Outputs map[string]any }
			err := json.Unmarshal([]byte(result.Metafile), &metadata)
			if err != nil {
				return buildError(err.Error())
			}

			var epPath string
			if isSourceMap {
				epPath = findOutputPathForEntryPoint(nonSourceMapFile, metadata) + ".map"
			} else {
				epPath = findOutputPathForEntryPoint(filePath, metadata)
			}

			epPath = filepath.Join(types.Config.RootPath, epPath)

			for _, out := range result.OutputFiles {
				if out.Path == epPath {
					output = out
					break
				}
			}
		}
	}

	if output.Path == "" {
		debug.FDebug(filePath, result.OutputFiles)
		return buildError("Could not find output file.")
	}

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

func buildError(msg string) (bool, string, string) {
	message := esbuild.Message{Text: msg}

	j, err := json.Marshal(message)
	if err != nil {
		return false, string(err.Error()), ""
	}

	return false, string(j), ""
}
