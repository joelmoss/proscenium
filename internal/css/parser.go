package css

import (
	"strings"

	"github.com/riking/cssparse/tokenizer"
)

type cssParser struct {
	tokens *cssTokenizer

	input    string
	output   string
	rootPath string

	// Map of mixin names and their contents.
	mixins cssMixins

	// The nesting level of each `:global` declaration, where each element is a pair of integers. The
	// first is the nesting level, and the second is 0 (ident) or 1 (function).
	globalRuleLevels [][2]int

	// The nesting level of each `:local` declaration, where each element is a pair of integers. The
	// first is the nesting level, and the second is 0 (ident) or 1 (function).
	localRuleLevels [][2]int

	// The hash value of the path. This is used to generate unique class names.
	pathHash string

	// Is the path a CSS module?
	isModule bool
}

func (p *cssParser) parse() (string, error) {
	for {
		result, ok := p.handleNextToken()
		if !ok {
			break
		}

		p.output += result
	}

	return p.output, nil
}

// Returns the next token, or nil if the end or an error is reached.
func (p *cssParser) nextToken() *tokenizer.Token {
	token := p.tokens.next()

	if token.Type.StopToken() {
		return nil
	}

	switch token.Type {
	case tokenizer.TokenCloseBrace:
		gcount := len(p.globalRuleLevels)
		if gcount > 0 {
			glevel := p.globalRuleLevels[gcount-1]
			if p.tokens.nesting == glevel[0] {
				p.tokens.log(":global is closed at %v", p.tokens.nesting)

				if glevel[1] > 0 {
					p.output += token.Value
				}

				p.globalRuleLevels = p.globalRuleLevels[:gcount-1]

				return p.nextToken()
			}
		}

		lcount := len(p.localRuleLevels)
		if lcount > 0 {
			llevel := p.localRuleLevels[lcount-1]
			if p.tokens.nesting == llevel[0] {
				p.tokens.log(":local is closed at %v", p.tokens.nesting)

				if llevel[1] > 0 {
					p.output += token.Value
				}

				p.localRuleLevels = p.localRuleLevels[:lcount-1]
				return p.nextToken()
			}
		}
	}

	return token
}

// Iterate over all tokens until we find a token matching `tokenType`. Returns the matching token
// and all tokens until that point. If `appendToOutput` is true, the token values will be appended
// to the output.
func (p *cssParser) outputUntilTokenType(tokenType tokenizer.TokenType, appendToOutput bool) (*tokenizer.Token, []*tokenizer.Token) {
	var tokensUntil []*tokenizer.Token

	for {
		token := p.nextToken()

		if token == nil || token.Type == tokenType {
			return token, tokensUntil
		}

		tokensUntil = append(tokensUntil, token)

		if appendToOutput {
			p.output += token.Render()
		}
	}
}

// Iterate over all tokens, passing the given iterator function `iterFn` for each iteration.
// Returning false from that function will break from the iteration.
func (p *cssParser) forEachToken(iterFn func(token *tokenizer.Token, nesting int) bool) {
	for {
		token := p.nextToken()

		iterResult := iterFn(token, p.tokens.nesting)
		if !iterResult {
			break
		}
	}
}

// Handle the next token and return the output, and whether we should continue. Accepts a
// `handleNextTokenUntilFunc` as an optional first argument, which is used to determine whether we
// should stop handling tokens. The function receives the current token, and should return true if
// it should stop handling tokens.
func (p *cssParser) handleNextToken(args ...interface{}) (string, bool) {
	token := p.nextToken()
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
			key, def := p.tokens.assignMixinDefinition()
			if key == "" {
				return token.Render(), true
			}

			p.mixins[key] = def

			return "", true
		} else if token.Value == "mixin" {
			var mixinIdent, uri string
			original := token.Render()

			// Iterate over all tokens until the next semicolon, to find the mixin name and URI.
			p.forEachToken(func(token *tokenizer.Token, nesting int) bool {
				original += token.Render()

				if token.Type == tokenizer.TokenSemicolon {
					// Current token is a semicolon, so we're done. But we need to skip it, otherwise we get
					// duplicates.
					p.nextToken()

					return false
				}

				switch token.Type {
				case tokenizer.TokenIdent:
					if mixinIdent == "" {
						mixinIdent = token.Value
					}

				case tokenizer.TokenURI:
					uri = token.Value
				}

				return true
			})

			p.tokens.log("%v, %v", mixinIdent, uri)

			if p.resolveMixin(mixinIdent, uri) {
				return "", true
			} else {
				t := p.tokens.currentToken()
				return original + t.Render(), true
			}
		}

	case tokenizer.TokenDelim:
		if p.isModule && token.Value == "." {
			nextT := p.nextToken()

			if nextT.Type == tokenizer.TokenIdent {
				// Return the unhashed class name if we are in a global rule.
				gcount := len(p.globalRuleLevels)
				if gcount > 0 {
					glevel := p.globalRuleLevels[gcount-1]

					if glevel[1] == 0 {
						return "." + nextT.Value, true
					}
				}

				p.tokens.log(".%s is module", nextT.Value)
				return "." + nextT.Value + p.pathHash, true
			}
		}

	case tokenizer.TokenColon:
		if p.isModule {
			nextT := p.nextToken()

			if nextT.Type == tokenizer.TokenFunction && nextT.Value == "local" {
				untilV, tokensUntil := p.outputUntilTokenType(tokenizer.TokenCloseParen, false)
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

				p.output += "." + className + p.pathHash

				untilV, _ = p.outputUntilTokenType(tokenizer.TokenOpenBrace, true)
				if untilV == nil {
					return "", false
				}

				p.tokens.log(":local is opened")

				p.output += untilV.Value

				p.localRuleLevels = append(p.localRuleLevels, [2]int{p.tokens.nesting, 1})

				token = p.nextToken()
			} else if nextT.Type == tokenizer.TokenFunction && nextT.Value == "global" {
				untilV, tokensUntil := p.outputUntilTokenType(tokenizer.TokenCloseParen, true)
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

				untilV, _ = p.outputUntilTokenType(tokenizer.TokenOpenBrace, true)
				if untilV == nil {
					return "", false
				}

				p.tokens.log(":global() is opened at %v", p.tokens.nesting)

				p.output += untilV.Value

				p.globalRuleLevels = append(p.globalRuleLevels, [2]int{p.tokens.nesting, 1})

				token = p.nextToken()
			} else if nextT.Type == tokenizer.TokenIdent && nextT.Value == "local" {
				untilV, tokensUntil := p.outputUntilTokenType(tokenizer.TokenOpenBrace, false)
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
						tmpOutput += t.Value + p.pathHash
					} else {
						tmpOutput += t.Value
					}
				}

				tmpOutput += untilV.Value

				// A class ident may not be present for the local rule, so we need to check for one. If
				// none is found we treat all children as local.
				if !containsClass {
					p.tokens.log(":local is opened")

					// No class is present, all children are local.
					p.localRuleLevels = append(p.localRuleLevels, [2]int{p.tokens.nesting, 0})
				} else {
					p.tokens.log(":local is opened")
					// p.output += "." + className + p.pathHash + untilV.Value
					p.output += strings.TrimSpace(tmpOutput)
				}

				token = p.nextToken()
			} else if nextT.Type == tokenizer.TokenIdent && nextT.Value == "global" {
				untilV, tokensUntil := p.outputUntilTokenType(tokenizer.TokenOpenBrace, false)
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
					// No class is present, all children are global.
					p.globalRuleLevels = append(p.globalRuleLevels, [2]int{p.tokens.nesting, 0})
					p.tokens.log(":global is opened at %v", p.tokens.nesting)

					token = p.nextToken()

				} else {
					p.tokens.log(":global is opened at %v", p.tokens.nesting)
					p.output += strings.TrimSpace(tmpOutput)
					token = p.nextToken()
				}

			} else {
				return token.Render() + nextT.Render(), true
			}
		}
	}

	return token.Render(), true
}
