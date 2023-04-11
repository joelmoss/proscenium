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

	filePath := p.tokens.tokenizers[p.tokens.position].filePath

	if uri != "" {
		// Resolve the path.
		absPath, ok := resolver.Absolute(uri, p.rootPath)
		if !ok {
			// Mixin path not found, so pass it through as-is.
			return false
		}

		// TODO: cache this!
		if !p.parseMixinDefinitions(absPath) {
			// Mixin file not found, so pass it through as-is.
			return false
		}

		filePath = absPath
	}

	def, ok := p.mixins[filePath+"#"+mixinIdent]
	if ok {
		p.tokens.insertTokens(def, filePath)
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

	tokens, err2 := newCssTokenizer(contents, filePath)
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
			key, def := tokens.parseMixinDefinition()
			if key == "" {
				return true
			}

			p.mixins[filePath+"#"+key] = def
		}

		return true
	})

	return true
}
