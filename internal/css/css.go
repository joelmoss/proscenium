package css

import (
	"joelmoss/proscenium/internal/types"
	"os"

	"github.com/riking/cssparse/tokenizer"
)

const debug = false

type handleNextTokenUntilFunc func(token *tokenizer.Token) bool

// Parse the given CSS file, and return the transformed CSS.
//
// Arguments:
//   - path: The absolute file system path of the file being parsed.
func ParseCssFile(path string) (string, error) {
	input, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return ParseCss(string(input), path)
}

// Parse the given CSS, and return the transformed CSS.
//
// Arguments:
//   - input: The CSS to parse.
//   - path: The absolute file system path of the file being parsed.
func ParseCss(input string, path string) (string, error) {
	t, _ := newCssTokenizer(input, path)

	p := cssParser{
		tokens:   t,
		input:    input,
		filePath: path,
		rootPath: types.Config.RootPath,
		mixins:   cssMixins{},
	}

	return p.parse()
}
