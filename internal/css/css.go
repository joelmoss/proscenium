package css

import (
	"crypto/sha1"
	"encoding/hex"
	"joelmoss/proscenium/internal/resolver"
	"os"
	"strings"

	"github.com/riking/cssparse/tokenizer"
)

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

	p := CssParser{
		input:    input,
		rootPath: root,
		tokens:   tokenizer.NewTokenizer(strings.NewReader(input)),
		pathHash: getSHA1Hash(path),
		isModule: isModule,
		mixins:   cssMixins{},
	}

	return p.parse()
}

type CssParser struct {
	tokens *tokenizer.Tokenizer

	input    string
	output   string
	rootPath string

	// Map of mixin names and their contents.
	mixins cssMixins

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

// Returns the next token, or nil if the end or an error is reached.
func (parser *CssParser) nextToken() *tokenizer.Token {
	token := parser.tokens.Next()

	if token.Type.StopToken() {
		return nil
	}

	if token.Type == tokenizer.TokenOpenBrace {
		parser.nestedLevels++
	} else if token.Type == tokenizer.TokenCloseBrace {
		parser.nestedLevels--

		gcount := len(parser.globalRuleLevels)
		if gcount > 0 {
			glevel := parser.globalRuleLevels[gcount-1]
			if parser.nestedLevels < glevel[0] {
				// pp.Printf("\n<<<<< :global is closed at line:%s, col:%s\n", token.Line, token.Column)

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
				// pp.Printf("\n<<<<< :local is closed at line:%s, col:%s\n", token.Line, token.Column)

				if llevel[1] > 0 {
					parser.output += token.Value
				}

				parser.localRuleLevels = parser.localRuleLevels[:lcount-1]
				return parser.nextToken()
			}
		}
	}

	// pp.Println(token.Type.String(), token, parser.nestedLevels, parser.globalRuleLevels)

	return &token
}

// Iterate over all tokens until we find a token matching `tokenType`. Returns the matching token
// and all tokens until that point. If `appendToOutput` is true, the token values will be appended
// tothe output.
func (parser *CssParser) outputUntilTokenType(tokenType tokenizer.TokenType, appendToOutput bool) (*tokenizer.Token, []*tokenizer.Token) {
	var tokensUntil []*tokenizer.Token

	for {
		token := parser.nextToken()

		if token == nil || token.Type == tokenType {
			return token, tokensUntil
		}

		tokensUntil = append(tokensUntil, token)

		if appendToOutput {
			parser.output += token.Render()
		}
	}
}

// Capture all output until the closing brace at the given level.
func (parser *CssParser) captureOutputUntilClosingBrace(level int) string {

	var captured string
	var untilFn handleNextTokenUntilFunc = func(token *tokenizer.Token) bool {
		return token.Type == tokenizer.TokenCloseBrace && parser.nestedLevels == level
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
			return token.Render(), false
		}
	}

	switch token.Type {
	case tokenizer.TokenAtKeyword:
		if token.Value == "define-mixin" {
			if parser.nestedLevels > 0 {
				// @define-mixin must be declared at the root level. Pass it through.
				return "@define-mixin", true
			}

			mixinIdent, _ := parser.outputUntilTokenType(tokenizer.TokenIdent, false)
			if mixinIdent == nil {
				return "", false
			}

			openingBrace, _ := parser.outputUntilTokenType(tokenizer.TokenOpenBrace, false)
			if openingBrace == nil {
				return "", false
			}

			// Fetch all output until the closing brace at the current level, and assign it to the mixin.
			parser.mixins[mixinIdent.Value] = parser.captureOutputUntilClosingBrace(0)
			token = parser.nextToken()
		} else if token.Value == "mixin" {
			var mixinIdent, uri string
			untilT, mixinTokens := parser.outputUntilTokenType(tokenizer.TokenSemicolon, false)
			if untilT == nil {
				return "", false
			}

			for _, t := range mixinTokens {
				switch t.Type {
				case tokenizer.TokenIdent:
					if mixinIdent == "" {
						mixinIdent = t.Value
					}

				case tokenizer.TokenURI:
					uri = t.Value
				}
			}

			if mixinIdent != "" {
				if uri != "" {
					originalDecl := "@mixin " + mixinIdent + ` from url("` + uri + `");`

					// Resolve the path.
					absPath, ok := resolver.Absolute(uri, parser.rootPath)
					if !ok {
						// Mixin path not found, so pass it through as-is.
						return originalDecl, true
					}

					// TODO: cache this!
					if !parser.parseMixinFile(absPath) {
						// Mixin file not found, so pass it through as-is.
						return originalDecl, true
					}

					mixin, ok := parser.mixins[absPath+"#"+mixinIdent]
					if ok {
						return mixin, true
					} else {
						// Mixin not found, so pass it through as-is.
						return originalDecl, true
					}
				} else {
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

	case tokenizer.TokenDelim:
		if parser.isModule && token.Value == "." {
			nextT := parser.nextToken()

			if nextT.Type == tokenizer.TokenIdent {
				// Return the unhashed class name if we are in a global rule.
				gcount := len(parser.globalRuleLevels)
				if gcount > 0 {
					glevel := parser.globalRuleLevels[gcount-1]
					if glevel[0] > 0 && glevel[1] < 1 {
						return "." + nextT.Value, true
					}
				}

				return "." + nextT.Value + parser.pathHash, true
			}
		}

	case tokenizer.TokenColon:
		if parser.isModule {
			nextT := parser.nextToken()

			if nextT.Type == tokenizer.TokenFunction && nextT.Value == "local" {
				untilV, tokensUntil := parser.outputUntilTokenType(tokenizer.TokenCloseParen, false)
				if untilV == nil {
					return "", false
				}

				var containsClass bool
				var className string
				for _, t := range tokensUntil {
					if t.Type == tokenizer.TokenDelim && t.Value == "." {
						containsClass = true
					} else if containsClass && t.Type == tokenizer.TokenIdent {
						className = t.Value
					}
				}

				if !containsClass {
					panic("local() must contain a class name")
				}

				parser.output += "." + className + parser.pathHash

				untilV, _ = parser.outputUntilTokenType(tokenizer.TokenOpenBrace, true)
				if untilV == nil {
					return "", false
				}

				// pp.Printf("\n>>>>> :local() is opened at line:%s, col:%s\n", untilV.Line, untilV.Column)

				parser.output += untilV.Value

				parser.localRuleLevels = append(parser.localRuleLevels, [2]int{parser.nestedLevels, 1})

				token = parser.nextToken()
			} else if nextT.Type == tokenizer.TokenFunction && nextT.Value == "global" {
				untilV, tokensUntil := parser.outputUntilTokenType(tokenizer.TokenCloseParen, true)
				if untilV == nil {
					return "", false
				}

				var containsClass bool
				for _, t := range tokensUntil {
					if t.Type == tokenizer.TokenDelim && t.Value == "." {
						containsClass = true
					}
				}

				if !containsClass {
					panic("global() must contain a class name")
				}

				untilV, _ = parser.outputUntilTokenType(tokenizer.TokenOpenBrace, true)
				if untilV == nil {
					return "", false
				}

				// pp.Printf("\n>>>>> :global() is opened at line:%s, col:%s\n", untilV.Line, untilV.Column)

				parser.output += untilV.Value

				parser.globalRuleLevels = append(parser.globalRuleLevels, [2]int{parser.nestedLevels, 1})

				token = parser.nextToken()
			} else if nextT.Type == tokenizer.TokenIdent && nextT.Value == "local" {
				untilV, tokensUntil := parser.outputUntilTokenType(tokenizer.TokenOpenBrace, false)
				if untilV == nil {
					return "", false
				}

				var tmpOutput string
				var containsClass bool
				for _, t := range tokensUntil {
					if t.Type == tokenizer.TokenDelim && t.Value == "." {
						containsClass = true
					}

					if containsClass && t.Type == tokenizer.TokenIdent {
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
			} else if nextT.Type == tokenizer.TokenIdent && nextT.Value == "global" {
				untilV, tokensUntil := parser.outputUntilTokenType(tokenizer.TokenOpenBrace, false)
				if untilV == nil {
					return "", false
				}

				var tmpOutput string
				var containsClass bool
				for _, t := range tokensUntil {
					if t.Type == tokenizer.TokenDelim && t.Value == "." {
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
				return token.Render() + nextT.Render(), true
			}
		}
	}

	return token.Render(), true
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

func getSHA1Hash(message string) string {
	hash := sha1.Sum([]byte(message))
	return hex.EncodeToString(hash[:])[0:8]
}
