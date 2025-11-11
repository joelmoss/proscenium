package css

import (
	"github.com/riking/cssparse/tokenizer"
)

type cssParser struct {
	tokens *cssTokenizer

	input    string
	output   string
	filePath string
	rootPath string

	// Map of mixin names and their contents.
	mixins cssMixins

	// The nesting level of each `:global` declaration, where each element is a pair of integers. The
	// first is the nesting level, and the second is 0 (ident) or 1 (function).
	globalRuleLevels [][2]int

	// The nesting level of each `:local` declaration, where each element is a pair of integers. The
	// first is the nesting level, and the second is 0 (ident) or 1 (function).
	localRuleLevels [][2]int
}

func (p *cssParser) parse() (string, error) {
	for {
		result, ok := p.handleNextToken()
		if !ok {
			break
		}

		p.append(result)
	}

	return p.output, nil
}

// Append the given input to the output.
func (p *cssParser) append(input string) {
	p.tokens.logOutput(input)
	p.output += input
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
					p.append(token.Value)
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
					p.append(token.Value)
				}

				p.localRuleLevels = p.localRuleLevels[:lcount-1]
				return p.nextToken()
			}
		}
	}

	return token
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
func (p *cssParser) handleNextToken(args ...any) (string, bool) {
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
		switch token.Value {
		case "define-mixin":
			key, def := p.tokens.parseMixinDefinition()
			if key == "" {
				return token.Render(), true
			}

			p.mixins[p.filePath+"#"+key] = def

			return "", true
		case "mixin":
			var mixinIdent, uri string

			// Capture the mixin declaration, so we can output it later if we fail to resolve it.
			original := token.Render()

			// Iterate over all tokens until the next semicolon, to find the mixin name and URI.
			p.forEachToken(func(token *tokenizer.Token, nesting int) bool {
				original += token.Render()

				if token.Type == tokenizer.TokenSemicolon {
					// Current token is a semicolon, so we're done. But we need to skip to the next token,
					// otherwise we get duplicates of the semicolon.
					p.nextToken()

					return false
				}

				switch token.Type {
				case tokenizer.TokenIdent: // get the mixin name.
					if mixinIdent == "" {
						mixinIdent = token.Value
					}

				case tokenizer.TokenURI: // get the mixin URI - if any.
					uri = token.Value
				}

				return true
			})

			if p.resolveMixin(mixinIdent, uri) {
				return "", true
			} else {
				t := p.tokens.currentToken()
				return original + t.Render(), true
			}
		}
	}

	return token.Render(), true
}
