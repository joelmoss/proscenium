package css

import (
	"joelmoss/proscenium/internal/types"
	"os"
)

const debug = false

// CssWarning represents a non-fatal warning generated during CSS parsing.
type CssWarning struct {
	Text     string
	FilePath string
	Line     int // 1-based
	Column   int // 0-based, in bytes
	Length   int // in bytes
	LineText string
}

// Parse the given CSS file, and return the transformed CSS.
//
// Arguments:
//   - path: The absolute file system path of the file being parsed.
func ParseCssFile(path string, cfg *types.ConfigT) (string, []CssWarning, error) {
	input, err := os.ReadFile(path)
	if err != nil {
		return "", nil, err
	}

	return ParseCss(string(input), path, cfg)
}

// Parse the given CSS, and return the transformed CSS.
//
// Arguments:
//   - input: The CSS to parse.
//   - path: The absolute file system path of the file being parsed.
func ParseCss(input string, path string, cfg *types.ConfigT) (string, []CssWarning, error) {
	return newCssParser(input, path, cfg).parse()
}

func newCssParser(input string, path string, cfg *types.ConfigT) *cssParser {
	t, _ := newCssTokenizer(input, path)

	return &cssParser{
		tokens:             t,
		input:              input,
		filePath:           path,
		cfg:                cfg,
		mixins:             cssMixins{},
		malformedMixins:    map[string]bool{},
		mixinFiles:         map[string]bool{},
		resolvedMixinFiles: map[mixinFileKey]resolvedMixinFile{},
	}
}
