package css

import (
	"os"
	"strings"

	"github.com/riking/cssparse/tokenizer"
)

type cssMixins map[string]string

// Parse the given `filePath` for mixin definitions, and append each to the given `mixins` map.
func (parser *CssParser) parseMixinFile(filePath string) bool {
	contents, err := os.ReadFile(filePath)
	if err != nil {
		return false
	}

	// Root nesting == 0
	var nesting int

	tokens := tokenizer.NewTokenizer(strings.NewReader(string(contents)))

	forEachToken(tokens, nesting, func(token tokenizer.Token, nesting int) bool {
		if token.Type == tokenizer.TokenAtKeyword && token.Value == "define-mixin" {
			var mixinName string

			// Find the mixin name (ident)
			forEachToken(tokens, nesting, func(token tokenizer.Token, nesting int) bool {
				if token.Type == tokenizer.TokenOpenBrace {
					if mixinName == "" {
						// We've reached the start of the @define-mixin declaration without finding a mixin
						// name, so skip through the entire block.
						skipBlock(tokens, nesting, nesting)
					}

					return false
				}

				if token.Type == tokenizer.TokenIdent {
					mixinName = token.Value
					return false
				}

				return true
			})

			if mixinName == "" {
				// Cannot find mixin name!
				return true
			}

			mixinContent := captureBlock(tokens, 1, nesting)
			parser.mixins[filePath+"#"+mixinName] = strings.TrimSpace(mixinContent)
		}

		return true
	})

	return true
}

// Capture the content between the opening and closing brace at the given `targetNesting` level.
func captureBlock(tokens *tokenizer.Tokenizer, targetNesting int, currentNesting int) string {
	var content string

	forEachToken(tokens, currentNesting, func(token tokenizer.Token, nesting int) bool {
		if targetNesting == nesting && token.Type == tokenizer.TokenOpenBrace {
			content = ""
			return true
		}

		if targetNesting == nesting && token.Type == tokenizer.TokenCloseBrace {
			return false
		}

		content += token.Render()

		return true
	})

	return content
}

// Skip the content between the opening and closing brace at the given `targetNesting` level.
func skipBlock(tokens *tokenizer.Tokenizer, targetNesting int, currentNesting int) {
	forEachToken(tokens, currentNesting, func(token tokenizer.Token, nesting int) bool {
		if targetNesting == nesting && token.Type == tokenizer.TokenCloseBrace {
			return false
		}

		return true
	})
}

func forEachToken(tokens *tokenizer.Tokenizer, nesting int, iterFn func(token tokenizer.Token, nesting int) bool) {
	for {
		token := tokens.Next()
		if token.Type.StopToken() {
			break
		}

		if token.Type == tokenizer.TokenOpenBrace {
			nesting++
		}

		if token.Type == tokenizer.TokenAtKeyword && token.Value == "define-mixin" && nesting > 0 {
			// @define-mixin must be declared at the root level - ignore it.
			// TODO: log a warning!
			skipBlock(tokens, nesting+1, nesting)
			continue
		}

		iterResult := iterFn(token, nesting)

		if token.Type == tokenizer.TokenCloseBrace {
			nesting--
		}

		if !iterResult {
			break
		}
	}
}
