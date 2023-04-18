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

	findAndInsertMixin := func(filePath string, mixinName string) bool {
		def, ok := p.mixins[filePath+"#"+mixinName]
		if ok {
			p.tokens.insertTokens(def, filePath, mixinName)
			return true
		}

		return false
	}

	if uri != "" {
		// Resolve the uri.
		absPath, ok := resolver.Absolute(uri, p.rootPath)
		if !ok {
			return false
		}

		if findAndInsertMixin(absPath, mixinIdent) {
			return true
		}

		if p.parseMixinDefinitions(absPath) {
			// We've successfully parsed the mixin file, so look up the definition.
			return findAndInsertMixin(absPath, mixinIdent)
		}
	} else {
		filePath := p.tokens.tokenizers[p.tokens.position].filePath
		return findAndInsertMixin(filePath, mixinIdent)
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
