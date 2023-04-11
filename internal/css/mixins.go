package css

import (
	"joelmoss/proscenium/internal/resolver"
	"os"

	"github.com/riking/cssparse/tokenizer"
)

type cssMixins map[string]string

// Takes a mixin name and uri, and builds the mixin definition as a map of tokens. These tokens are
// then inserted into the tokenizer stream, and will be parsed as part of the current stylesheet.
func (p *cssParser) resolveMixin(mixinIdent string, uri string) bool {
	if mixinIdent == "" {
		return false
	}

	output := func() string {
		if uri != "" {
			// Resolve the path.
			absPath, ok := resolver.Absolute(uri, p.rootPath)
			if !ok {
				// Mixin path not found, so pass it through as-is.
				return ""
			}

			// TODO: cache this!
			if !p.parseMixinDefinitions(absPath) {
				// Mixin file not found, so pass it through as-is.
				return ""
			}

			mixin, ok := p.mixins[absPath+"#"+mixinIdent]
			if ok {
				return mixin
			}
		} else {
			mixin, ok := p.mixins[mixinIdent]
			if ok {
				return mixin
			}
		}

		return ""
	}()

	p.tokens.log("%s%s :: %v", uri, mixinIdent, output)

	// We have output from the resolved mixin, so tokenize it and insert it into the stream.
	if output != "" {
		p.tokens.insertTokens(output)
		return true
	}

	return false
}

// Parse the given `filePath` for mixin definitions, and append each to the given `mixins` map. This
// will ignore everything except mixin definitions, and does not parse the mixin definition contents.
// The parsing is done when the mixin is included.
func (p *cssParser) parseMixinDefinitions(filePath string) bool {
	contents, err := os.ReadFile(filePath)
	if err != nil {
		return false
	}

	tokens, err2 := newCssTokenizer(contents)
	if err2 != nil {
		return false
	}

	tokens.next()

	// Iterate through all the tokens in the file, and find any @define-mixin declarations at the root
	// nesting. Definition blocks are not parsed here.
	tokens.forEachToken(func(token *tokenizer.Token) bool {
		if token.Type.StopToken() {
			return false
		}

		if token.Type == tokenizer.TokenAtKeyword && token.Value == "define-mixin" {
			key, def := tokens.assignMixinDefinition()
			if key == "" {
				return true
			}

			p.mixins[filePath+"#"+key] = def
		}

		return true
	})

	// Root nesting == 0
	// var nesting int

	// forEachToken(tokens, nesting, func(token tokenizer.Token, nesting int) bool {
	// 	if token.Type == tokenizer.TokenAtKeyword && token.Value == "define-mixin" {
	// 		var mixinName string

	// 		// Find the mixin name (ident)
	// 		forEachToken(tokens, nesting, func(token tokenizer.Token, nesting int) bool {
	// 			if token.Type == tokenizer.TokenOpenBrace {
	// 				if mixinName == "" {
	// 					// We've reached the start of the @define-mixin declaration without finding a mixin
	// 					// name, so skip through the entire block.
	// 					skipBlock(tokens, nesting, nesting)
	// 				}

	// 				return false
	// 			}

	// 			if token.Type == tokenizer.TokenIdent {
	// 				mixinName = token.Value
	// 				return false
	// 			}

	// 			return true
	// 		})

	// 		if mixinName == "" {
	// 			// Cannot find mixin name!
	// 			return true
	// 		}

	// 		mixinContent := captureBlock(tokens, 1, nesting, filePath, p)
	// 		p.mixins[filePath+"#"+mixinName] = strings.TrimSpace(mixinContent)
	// 	}

	// 	return true
	// })

	return true
}
