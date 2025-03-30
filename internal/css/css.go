package css

import (
	"joelmoss/proscenium/internal/types"
	"joelmoss/proscenium/internal/utils"
	"os"
	"strings"

	"github.com/riking/cssparse/tokenizer"
)

const debug = false

type handleNextTokenUntilFunc func(token *tokenizer.Token) bool

// Parse the given CSS file, and return the transformed CSS.
//
// Arguments:
//   - path: The absolute file system path of the file being parsed.
//   - root: The root directory of the project.
func ParseCssFile(path string, pathHash string) (string, error) {
	input, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return ParseCss(string(input), path, pathHash)
}

// Parse the given CSS, and return the transformed CSS.
//
// Arguments:
//   - input: The CSS to parse.
//   - path: The absolute file system path of the file being parsed.
//   - root: The root directory of the project.
func ParseCss(input string, path string, pathHash string) (string, error) {
	isModule := false
	if strings.HasSuffix(path, ".module.css") {
		isModule = true

		if pathHash == "" {
			pathHash = utils.ToDigest(path)
		}
	} else {
		pathHash = ""
	}

	t, _ := newCssTokenizer(input, path)

	p := cssParser{
		tokens:   t,
		input:    input,
		filePath: path,
		rootPath: types.Config.RootPath,
		pathHash: pathHash,
		isModule: isModule,
		mixins:   cssMixins{},
	}

	return p.parse()
}
