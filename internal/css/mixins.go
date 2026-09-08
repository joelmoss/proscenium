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

	search := "@mixin " + mixinIdent

	// Set when a mixin was found but refused as a cycle, so the "not defined" warnings below -
	// which mean "no such mixin" - are not also emitted for it.
	cycled := false

	findAndInsertMixin := func(filePath string, mixinName string) bool {
		key := filePath + "#" + mixinName

		def, ok := p.mixins[key]
		if !ok {
			return false
		}

		// A mixin already being expanded cannot be expanded again. `@define-mixin m{@mixin m;}`
		// pushed a fresh tokenizer per invocation and never returned, growing the output and the
		// tokenizer stack until the process died; two files including each other through `url()`
		// fail the same way. Cycle detection rather than a depth cap, because legitimate nesting
		// has no natural limit and a cycle is never legitimate.
		if p.tokens.isExpanding(key) {
			p.addWarning(search, "Mixin %q includes itself", mixinName)
			cycled = true

			return false
		}

		p.tokens.insertTokens(def, filePath, key)

		return true
	}

	if uri != "" {
		// Resolve the uri.
		_, absPath, err := resolver.Resolve(uri, p.tokens.currentFilePath(), p.cfg)
		if err != nil {
			p.addWarning(search, "Could not resolve mixin file %q for mixin %q", uri, mixinIdent)
			return false
		}

		if findAndInsertMixin(absPath, mixinIdent) {
			return true
		}

		// Already refused as a cycle, so re-parsing the file and asking again would only refuse
		// it a second time, and warn twice for one declaration.
		if cycled {
			return false
		}

		if p.parseMixinDefinitions(absPath) {
			// We've successfully parsed the mixin file, so look up the definition.
			if findAndInsertMixin(absPath, mixinIdent) {
				return true
			}
			if !cycled {
				p.addWarning(search, "Mixin %q not found in %q", mixinIdent, absPath)
			}

			return false
		}

		p.addWarning(search, "Could not resolve mixin file %q for mixin %q", uri, mixinIdent)
		return false
	} else {
		filePath := p.tokens.currentFilePath()
		if findAndInsertMixin(filePath, mixinIdent) {
			return true
		}
		if !cycled {
			p.addWarning(search, "Mixin %q not defined in %q", mixinIdent, filePath)
		}

		return false
	}
}

// Parse the given `filePath` for mixin definitions, and append each to the given `mixins` map. This
// will ignore everything except mixin definitions, and does not parse the mixin definition
// contents. The parsing is done when the mixin is included.
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
		// `forEachToken` stops at the end of the input on its own; this stops on the error and "bad"
		// tokens too, which it deliberately passes through as content.
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
