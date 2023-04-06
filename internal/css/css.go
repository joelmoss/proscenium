package css

import (
	"crypto/sha1"
	"encoding/hex"
	"os"
	"strings"

	"github.com/gorilla/css/scanner"
)

type handleNextTokenUntilFunc func(token *scanner.Token) bool

func ParseCssFile(path string) (string, error) {
	input, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return ParseCss(string(input), path)
}

type CssParser struct {
	tokens *scanner.Scanner

	input  string
	output string

	// Map of mixin names to their contents.
	mixins map[string]string

	// The level at which the current global rule is declared. This is used to determine whether rules
	// should be global or local. If the current rule is nested equal to, or deeper than where the
	// global rule was declared, then the rule is global. Otherwise, it's local.
	nestedLevels int

	// Count of number of nesting levels, which is essentially just the count of each opening curly
	// brace `{`.
	globalRuleStartsAtLevel int

	// The hash value of the path. This is used to generate unique class names.
	pathHash string

	// Is the path a CSS module?
	isModule bool
}

func ParseCss(input string, path string) (string, error) {
	isModule := false
	if strings.HasSuffix(path, ".module.css") {
		isModule = true
	}

	p := CssParser{
		input:    input,
		tokens:   scanner.New(input),
		pathHash: getSHA1Hash(path),
		isModule: isModule,
		mixins:   map[string]string{},
	}

	return p.parse()
}

// Returns the next token, or nil if the end or an error is reached.
func (parser *CssParser) nextToken() *scanner.Token {
	token := parser.tokens.Next()

	if token.Type == scanner.TokenEOF || token.Type == scanner.TokenError {
		return nil
	}

	if token.Type == scanner.TokenChar {
		if token.Value == "{" {
			parser.nestedLevels++
		} else if token.Value == "}" {
			parser.nestedLevels--

			if parser.nestedLevels < parser.globalRuleStartsAtLevel {
				parser.globalRuleStartsAtLevel = 0
				return parser.nextToken()
			}
		}
	}

	// pp.Println(token.Type.String(), token, parser.nestedLevels)

	return token
}

// Iterate over all tokens until we find a token matching `value`. Returns the matching token and
// all tokens until that point. If `appendToOutput` is true, the token values will be appended to
// the output.
func (parser *CssParser) outputUntilValue(value string, appendToOutput bool) (*scanner.Token, []*scanner.Token) {
	var tokensUntil []*scanner.Token

	for {
		token := parser.nextToken()

		if token == nil || token.Value == value {
			return token, tokensUntil
		}

		tokensUntil = append(tokensUntil, token)

		if appendToOutput {
			parser.output += token.Value
		}
	}
}

// Like `outputUntilValue`, but matches on `tokenType` instead of value.
func (parser *CssParser) outputUntilTokenType(tokenType any, appendToOutput bool) (*scanner.Token, []*scanner.Token) {
	var tokensUntil []*scanner.Token

	for {
		token := parser.nextToken()

		if token == nil || token.Type == tokenType {
			return token, tokensUntil
		}

		tokensUntil = append(tokensUntil, token)

		if appendToOutput {
			parser.output += token.Value
		}
	}
}

// Capture all output until the closing brace at the given level.
func (parser *CssParser) captureOutputUntilClosingBrace(level int) string {

	var captured string
	var untilFn handleNextTokenUntilFunc = func(token *scanner.Token) bool {
		return token.Type == scanner.TokenChar && token.Value == "}" && parser.nestedLevels == level
	}

	for {
		result, ok := parser.handleNextToken(untilFn)
		if !ok {
			break
		}

		captured += result
	}

	return strings.TrimSpace(captured)
}

// Handle the next token and return the output and whether we should continue. Accepts a
// `func handleNextTokenUntilFunc` as an optional argument, which is used to determine whether we
// should stop handling tokens. The function receives the current token, and should return true if
// it should stop handling tokens.
func (parser *CssParser) handleNextToken(args ...interface{}) (string, bool) {
	token := parser.nextToken()
	if token == nil {
		return "", false
	}

	switch len(args) {
	case 1:
		untilFn := args[0].(handleNextTokenUntilFunc)
		if untilFn(token) {
			return token.Value, false
		}
	}

	switch token.Type {
	case scanner.TokenAtKeyword:
		if token.Value == "@define-mixin" {
			if parser.nestedLevels > 0 {
				// @define-mixin must be declared at the root level.
				return token.Value, true
			}

			mixinIdent, _ := parser.outputUntilTokenType(scanner.TokenIdent, false)
			if mixinIdent == nil {
				return "", false
			}

			openingBrace, _ := parser.outputUntilValue("{", false)
			if openingBrace == nil {
				return "", false
			}

			// Fetch all output until the closing brace at the current level, and assign it to the mixin.
			parser.mixins[mixinIdent.Value] = parser.captureOutputUntilClosingBrace(0)
			token = parser.nextToken()
		}

		if token.Value == "@mixin" {
			var mixinIdent, uri string
		useMixinLoop:
			for {
				token = parser.nextToken()

				switch token.Type {
				case scanner.TokenIdent:
					if mixinIdent == "" {
						mixinIdent = token.Value
					}

				case scanner.TokenURI:
					uri = token.Value

				case scanner.TokenChar:
					if token.Value == ";" {
						break useMixinLoop
					}
				}
			}

			if mixinIdent != "" {
				if uri != "" {
					// Fetch the mixin from the given URI using esbuild's resolver, then read and parse the
					// file for mixin definitions only.
					// re := regexp.MustCompile(`(?m)^url\(['"](.+)['"]\)$`)

					// FIXME: Hard code the root path for now.
					// root := "/Users/joelmoss/dev/proscenium/test/internal"
					// absPath := path.Join(root, re.FindStringSubmatch(uri)[1])

					// Resolve the path.
					// ?

					// parseMixinFile(absPath)

					return "@mixin " + mixinIdent + " from " + uri + ";", true
				} else {
					// Fetch the mixin from local.
					mixin, ok := parser.mixins[mixinIdent]
					if ok {
						return mixin, true
					} else {
						// Mixin not found, so pass it through as-is.
						return "@mixin " + mixinIdent + ";", true
					}
				}
			}
		}

	case scanner.TokenChar:
		if parser.isModule {
			if token.Value == "." {
				nextT := parser.nextToken()

				if nextT.Type == scanner.TokenIdent {
					// Return the unhashed class if we are in a global rule.
					if parser.globalRuleStartsAtLevel > 0 {
						return "." + nextT.Value, true
					}

					return "." + nextT.Value + parser.pathHash, true
				}
			} else if token.Value == ":" {
				nextT := parser.nextToken()

				if nextT.Type == scanner.TokenFunction && nextT.Value == "global(" {
					untilV, _ := parser.outputUntilValue(")", true)
					if untilV == nil {
						return "", false
					}

					token = parser.nextToken()
				} else if nextT.Type == scanner.TokenIdent && nextT.Value == "global" {
					untilV, tokensUntil := parser.outputUntilValue("{", false)
					if untilV == nil {
						return "", false
					}

					var tmpOutput string
					var containsClass bool
					for _, t := range tokensUntil {
						if t.Type == scanner.TokenChar && t.Value == "." {
							containsClass = true
						}

						tmpOutput += t.Value
					}

					tmpOutput += untilV.Value

					// A class ident may not be present for the global rule, so we need to check for one. If
					// none is found we treat all children as global.
					if !containsClass {
						// No class is present, all children are global.
						parser.globalRuleStartsAtLevel = parser.nestedLevels
					} else {
						parser.output += strings.TrimSpace(tmpOutput)
					}

					token = parser.nextToken()
				} else {
					return token.Value + nextT.Value, true
				}
			}
		}
	}

	return token.Value, true
}

func (parser *CssParser) parse() (string, error) {
	for {
		result, ok := parser.handleNextToken()
		if !ok {
			break
		}

		parser.output += result
	}

	return parser.output, nil
}

// func parseMixinFile(filePath string) (map[], bool) {
// 	input, err := os.ReadFile(filePath)
// 	if err != nil {
// 		return nil, false
// 	}

// 	return input, true
// }

func getSHA1Hash(message string) string {
	hash := sha1.Sum([]byte(message))
	return hex.EncodeToString(hash[:])[0:8]
}

// Find the given local mixin as defined by `name`.
// func findLocalMixin(name string) (string, bool) {
// 	return name, false
// }
