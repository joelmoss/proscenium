package css

import (
	"joelmoss/proscenium/internal/resolver"
	"joelmoss/proscenium/internal/utils"
	"os"

	"github.com/riking/cssparse/tokenizer"
)

type cssMixins map[string]string

type mixinFileKey struct {
	uri      string
	importer string
}

type resolvedMixinFile struct {
	absPath string
	err     error
}

// Caps on how much one parse may expand mixins. Cycle detection cannot stop a chain where each
// mixin includes the one before it twice, which doubles at every level: 22 levels is 4 million
// expansions, and a few hundred bytes of CSS, from a package's mixin file too, could pin a worker
// for minutes. Each cap bounds a different cost: the count, the work per expansion of a tiny body;
// the bytes, the work of a large one; and the depth, the tokenizer each open mixin keeps, and the
// stack that cycle detection scans on every `@mixin`. The count is high enough for a design system
// (10,000 was not), and nesting a hundred deep is never written by hand. The README and the "mixin
// expansion limits" specs state all three values.
const (
	maxMixinExpansions = 100_000
	maxMixinBytes      = 4 << 20
	maxMixinDepth      = 100
)

// Takes a mixin name and uri, and builds the mixin definition as a map of tokens. These tokens are
// then inserted into the tokenizer stream, and will be parsed as part of the current stylesheet.
func (p *cssParser) resolveMixin(mixinIdent string, uri string) bool {
	// Past the expansion limits every `@mixin` is refused, so none is worth resolving or looking up.
	if mixinIdent == "" || p.mixinLimitExceeded {
		return false
	}

	search := "@mixin " + mixinIdent

	// Set when a mixin was found but refused - as a cycle, as malformed, or past the expansion
	// limits - so the "not defined" warnings below, which mean "no such mixin", are not also
	// emitted for it.
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
		// fail the same way. Cycle detection, because a cycle is never legitimate: `maxMixinDepth`
		// would stop one only after a hundred pointless expansions, and is there to bound the cost
		// of deep nesting, not to catch it.
		if p.tokens.isExpanding(key) {
			p.addWarning(search, "Mixin %q includes itself", mixinName)
			refused = true

			return false
		}

		if p.mixinExpansions >= maxMixinExpansions || p.mixinBytes+len(def) > maxMixinBytes ||
			p.tokens.openMixins >= maxMixinDepth {
			// Sets the latch, which refuses every later `@mixin` at the top of resolveMixin, so this
			// warns once. Past `maxWarnings` too: it is the only word on why the rest of the
			// stylesheet's mixins are left as written.
			p.warnings = append(p.warnings, p.newWarning(search, "Mixin %q not expanded: the "+
				"stylesheet exceeds the limit of %d mixin expansions, %d bytes of mixin definitions, or %d "+
				"levels of mixin nesting", mixinName, maxMixinExpansions, maxMixinBytes, maxMixinDepth))
			p.mixinLimitExceeded = true
			refused = true

			return false
		}

		p.mixinExpansions++
		p.mixinBytes += len(def)
		p.tokens.insertTokens(def, filePath, mixinName)

		return true
	}

	if uri != "" {
		absPath, err := p.resolveMixinFile(uri)
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

		// Already refused - as a cycle, or past the expansion limits - so re-parsing the file and
		// asking again would only refuse it a second time, and warn twice for one declaration.
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

// Resolves the uri of a mixin file, once per uri and importing file in a parse. Resolving runs
// esbuild's resolver, about 1ms, and a uri that does not resolve is no expansion, so the expansion
// caps do not count it: a doubling chain whose last mixin used a few such uris took minutes.
func (p *cssParser) resolveMixinFile(uri string) (string, error) {
	key := mixinFileKey{uri, p.tokens.currentFilePath()}
	if r, ok := p.resolvedMixinFiles[key]; ok {
		return r.absPath, r.err
	}

	_, absPath, err := resolver.Resolve(uri, key.importer, p.cfg)
	p.resolvedMixinFiles[key] = resolvedMixinFile{absPath, err}

	return absPath, err
}

// Parses the mixin definitions in `filePath`, once per file in a parse: a mixin missing from it is
// no expansion, so the expansion caps do not count it, and each miss re-read the whole file - a
// doubling chain whose last mixin used one took minutes.
func (p *cssParser) parseMixinDefinitions(filePath string) bool {
	if parsed, ok := p.mixinFiles[filePath]; ok {
		return parsed
	}

	parsed := p.readMixinDefinitions(filePath)
	p.mixinFiles[filePath] = parsed

	return parsed
}

// Reads `filePath` for mixin definitions, and adds each to `p.mixins`. This ignores everything
// except mixin definitions, and does not parse their contents: that is done when one is included.
func (p *cssParser) readMixinDefinitions(filePath string) bool {
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
