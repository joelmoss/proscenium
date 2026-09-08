package css

import (
	"fmt"
	"joelmoss/proscenium/internal/types"
	"strings"

	"github.com/riking/cssparse/tokenizer"
)

type cssParser struct {
	tokens *cssTokenizer

	input    string
	output   strings.Builder
	filePath string
	cfg      *types.ConfigT

	// Map of mixin names and their contents.
	mixins cssMixins

	// Warnings accumulated during parsing.
	warnings []CssWarning
}

func (p *cssParser) parse() (string, []CssWarning, error) {
	for {
		result, ok := p.handleNextToken()
		if !ok {
			break
		}

		p.append(result)
	}

	return p.output.String(), p.warnings, nil
}

// addWarning adds a warning associated with the current file. The search string is used to locate
// the warning position within the input by searching for it starting from the current output length.
func (p *cssParser) addWarning(search string, format string, args ...any) {
	w := CssWarning{
		Text:     fmt.Sprintf(format, args...),
		FilePath: p.filePath,
	}

	if search != "" {
		// Use output length as approximate position in input. Clamp to valid range since mixin
		// expansion can make output longer than input.
		startFrom := p.output.Len() - len(search)
		if startFrom < 0 {
			startFrom = 0
		} else if startFrom > len(p.input) {
			startFrom = 0
		}

		idx := strings.Index(p.input[startFrom:], search)
		if idx >= 0 {
			idx += startFrom
		} else if idx = strings.Index(p.input, search); idx < 0 {
			// Not found at all; skip location info.
			p.warnings = append(p.warnings, w)
			return
		}

		prefix := p.input[:idx]
		w.Line = strings.Count(prefix, "\n") + 1
		w.Length = len(search)

		lastNL := strings.LastIndex(prefix, "\n")
		if lastNL == -1 {
			w.Column = idx
		} else {
			w.Column = idx - lastNL - 1
		}

		lineStart := lastNL + 1
		lineEnd := strings.Index(p.input[lineStart:], "\n")
		if lineEnd == -1 {
			w.LineText = p.input[lineStart:]
		} else {
			w.LineText = p.input[lineStart : lineStart+lineEnd]
		}
	}

	p.warnings = append(p.warnings, w)
}

// Append the given input to the output.
func (p *cssParser) append(input string) {
	p.tokens.logOutput(input)
	p.output.WriteString(input)
}

// Iterate over all tokens, passing the given iterator function `iterFn` for each iteration.
// Returning false from that function will break from the iteration.
//
// Iteration stops at the end of the stream, so `iterFn` is guaranteed a renderable token and can
// only decide whether to keep going. A stop token ends the stylesheet here just as it does in
// `handleNextToken`, so a truncated declaration terminates rather than handing the callback the
// end of the stream.
func (p *cssParser) forEachToken(iterFn func(token *tokenizer.Token) bool) {
	for {
		token := p.tokens.next()
		if token.Type.StopToken() {
			break
		}

		if !iterFn(token) {
			break
		}
	}
}

// Handle the next token and return the output, and whether we should continue.
func (p *cssParser) handleNextToken() (string, bool) {
	token := p.tokens.next()
	if token.Type.StopToken() {
		return "", false
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
			var original strings.Builder
			original.WriteString(token.Render())

			// Iterate over all tokens until the next semicolon, to find the mixin name and URI.
			p.forEachToken(func(token *tokenizer.Token) bool {
				original.WriteString(token.Render())

				if token.Type == tokenizer.TokenSemicolon {
					// Current token is a semicolon, so we're done. But we need to skip to the next token,
					// otherwise we get duplicates of the semicolon.
					p.tokens.next()

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
				return original.String() + t.Render(), true
			}
		}
	}

	return token.Render(), true
}
