package css

import (
	"crypto/sha1"
	"encoding/hex"
	"os"
	"strings"

	"github.com/gorilla/css/scanner"
	"github.com/k0kubun/pp/v3"
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

	// The nesting level of each `:global` declaration.
	globalRuleLevels [][2]int

	// The nesting level of each `:local` declaration.
	localRuleLevels [][2]int

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

			gcount := len(parser.globalRuleLevels)
			if gcount > 0 {
				glevel := parser.globalRuleLevels[gcount-1]
				if parser.nestedLevels < glevel[0] {
					pp.Printf("\n<<<<< :global is closed at line:%s, col:%s\n", token.Line, token.Column)

					if glevel[1] > 0 {
						parser.output += token.Value
					}

					parser.globalRuleLevels = parser.globalRuleLevels[:gcount-1]
					return parser.nextToken()
				}
			}

			lcount := len(parser.localRuleLevels)
			if lcount > 0 {
				llevel := parser.localRuleLevels[lcount-1]
				if parser.nestedLevels < llevel[0] {
					pp.Printf("\n<<<<< :local is closed at line:%s, col:%s\n", token.Line, token.Column)

					if llevel[1] > 0 {
						parser.output += token.Value
					}

					parser.localRuleLevels = parser.localRuleLevels[:lcount-1]
					return parser.nextToken()
				}
			}
		}
	}

	// pp.Println(token.Type.String(), token, parser.nestedLevels, parser.globalRuleLevels)

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
					// Return the unhashed class name if we are in a global rule.

					isGlobal := false
					gcount := len(parser.globalRuleLevels)
					if gcount > 0 {
						glevel := parser.globalRuleLevels[gcount-1]
						if glevel[0] > 0 && glevel[1] < 1 {
							isGlobal = true
							return "." + nextT.Value, true
						}
					}

					isLocal := false
					lcount := len(parser.localRuleLevels)
					if lcount > 0 {
						llevel := parser.localRuleLevels[lcount-1]
						if llevel[0] > 0 && llevel[1] < 1 {
							isLocal = true
							// return "." + nextT.Value, true
						}
					}

					pp.Println("--------------------isGlobal:", isGlobal)
					pp.Println("isLocal:", isLocal)

					return "." + nextT.Value + parser.pathHash, true
				}
			} else if token.Value == ":" {
				nextT := parser.nextToken()

				if nextT.Type == scanner.TokenFunction && nextT.Value == "local(" {
					untilV, tokensUntil := parser.outputUntilValue(")", false)
					if untilV == nil {
						return "", false
					}

					var containsClass bool
					var className string
					for _, t := range tokensUntil {
						if t.Type == scanner.TokenChar && t.Value == "." {
							containsClass = true
						} else if containsClass && t.Type == scanner.TokenIdent {
							className = t.Value
						}
					}

					if !containsClass {
						panic("local() must contain a class name")
					}

					parser.output += "." + className + parser.pathHash

					untilV, _ = parser.outputUntilValue("{", true)
					if untilV == nil {
						return "", false
					}

					pp.Printf("\n>>>>> :local() is opened at line:%s, col:%s\n", untilV.Line, untilV.Column)

					parser.output += untilV.Value

					parser.localRuleLevels = append(parser.localRuleLevels, [2]int{parser.nestedLevels, 1})

					token = parser.nextToken()
				} else if nextT.Type == scanner.TokenFunction && nextT.Value == "global(" {
					untilV, tokensUntil := parser.outputUntilValue(")", true)
					if untilV == nil {
						return "", false
					}

					var containsClass bool
					for _, t := range tokensUntil {
						if t.Type == scanner.TokenChar && t.Value == "." {
							containsClass = true
						}
					}

					if !containsClass {
						panic("global() must contain a class name")
					}

					untilV, _ = parser.outputUntilValue("{", true)
					if untilV == nil {
						return "", false
					}

					pp.Printf("\n>>>>> :global() is opened at line:%s, col:%s\n", untilV.Line, untilV.Column)

					parser.output += untilV.Value

					parser.globalRuleLevels = append(parser.globalRuleLevels, [2]int{parser.nestedLevels, 1})

					token = parser.nextToken()
				} else if nextT.Type == scanner.TokenIdent && nextT.Value == "local" {
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

						if containsClass && t.Type == scanner.TokenIdent {
							tmpOutput += t.Value + parser.pathHash
						} else {
							tmpOutput += t.Value
						}
					}

					tmpOutput += untilV.Value

					// A class ident may not be present for the local rule, so we need to check for one. If
					// none is found we treat all children as local.
					if !containsClass {
						// pp.Printf("\n>>>>> :local is opened at line:%s, col:%s\n", untilV.Line, untilV.Column)

						// No class is present, all children are local.
						parser.localRuleLevels = append(parser.localRuleLevels, [2]int{parser.nestedLevels, 0})
					} else {
						// pp.Printf("\n>>>>> :local %s is opened at line:%s, col:%s\n", tmpOutput, untilV.Line, untilV.Column)
						// parser.output += "." + className + parser.pathHash + untilV.Value
						parser.output += strings.TrimSpace(tmpOutput)
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
						// pp.Printf("\n>>>>> :global is opened at line:%s, col:%s\n", untilV.Line, untilV.Column)

						// No class is present, all children are global.
						parser.globalRuleLevels = append(parser.globalRuleLevels, [2]int{parser.nestedLevels, 0})
					} else {
						// pp.Printf("\n>>>>> :global %s is opened at line:%s, col:%s\n", tmpOutput, untilV.Line, untilV.Column)
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
