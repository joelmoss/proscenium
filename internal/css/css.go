package css

import (
	"crypto/sha1"
	"encoding/hex"
	"os"
	"strings"

	"github.com/riking/cssparse/tokenizer"
)

const debug = true

type handleNextTokenUntilFunc func(token *tokenizer.Token) bool

// Parse the given CSS file, and return the transformed CSS.
//
// Arguments:
//   - path: The path of the file being parsed.
//   - root: The root directory of the project.
func ParseCssFile(path string, root string) (string, error) {
	input, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return ParseCss(string(input), path, root)
}

// Parse the given CSS, and return the transformed CSS.
//
// Arguments:
//   - input: The CSS to parse.
//   - path: The path of the file being parsed.
//   - root: The root directory of the project.
func ParseCss(input string, path string, root string) (string, error) {
	isModule := false
	if strings.HasSuffix(path, ".module.css") {
		isModule = true
	}

	t, _ := newCssTokenizer(input)

	p := cssParser{
		tokens:   t,
		input:    input,
		rootPath: root,
		pathHash: getSHA1Hash(path),
		isModule: isModule,
		mixins:   cssMixins{},
	}

	return p.parse()
}

func getSHA1Hash(message string) string {
	hash := sha1.Sum([]byte(message))
	return hex.EncodeToString(hash[:])[0:8]
}
