package css

import (
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/utils"
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

	// Set when a mixin was found but refused - as a cycle, or as malformed - so the "not defined"
	// warnings below, which mean "no such mixin", are not also emitted for it.
	refused := false

	findAndInsertMixin := func(filePath string, mixinName string) bool {
		key := filePath + "#" + mixinName

		if p.malformedMixins[key] {
			p.addWarning(search, "Mixin %q in %q is malformed CSS", mixinName, filePath)
			refused = true

			return false
		}

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
			refused = true

			return false
		}

		p.tokens.insertTokens(def, filePath, mixinName)

		return true
	}

	if uri != "" {
		// Resolve the uri.
		_, absPath, err := resolver.Resolve(uri, p.tokens.currentFilePath(), p.cfg)
		if err != nil {
			// A panic the resolver recovered is not a missing file. Keep it, so the parse fails
			// with the stack instead of a warning beside an unexpanded mixin.
			if utils.IsPanicError(err) {
				p.err = err

				return false
			}

			// With the reason, because the fall-through warning below has the same first half:
			// a file that resolves but cannot be read reports itself in the same words.
			p.addWarning(search, "Could not resolve mixin file %q for mixin %q: %s", uri, mixinIdent, err)
			return false
		}

		if findAndInsertMixin(absPath, mixinIdent) {
			return true
		}

		// Already refused as a cycle, so re-parsing the file and asking again would only refuse
		// it a second time, and warn twice for one declaration.
		if refused {
			return false
		}

		if p.parseMixinDefinitions(absPath) {
			// We've successfully parsed the mixin file, so look up the definition.
			if findAndInsertMixin(absPath, mixinIdent) {
				return true
			}
			if !refused {
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
		if !refused {
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
		if token.Type == tokenizer.TokenAtKeyword && token.Value == "define-mixin" {
			tokens.malformed = false
			key, def := tokens.parseMixinDefinition()
			if key == "" {
				return true
			}

			// A bad token in the definition: the tokenizer cannot write it back as written, so the
			// mixin is refused with a warning rather than expanded lossily, or made to return the
			// whole valid stylesheet that uses it unchanged.
			// The last definition of a name wins, malformed or not.
			k := filePath + "#" + key
			if tokens.malformed {
				p.malformedMixins[k] = true
				delete(p.mixins, k)

				return true
			}

			p.mixins[k] = def
			delete(p.malformedMixins, k)
		}

		return true
	})

	return true
}
