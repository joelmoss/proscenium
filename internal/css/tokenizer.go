package css

import (
	"strings"

	"github.com/joelmoss/esbuild-internal/css_lexer"
	"github.com/joelmoss/esbuild-internal/logger"
)

// A token, with its text exactly as written and, for an identifier, at-keyword, url, string or
// function, its value with escapes decoded.
type cssToken struct {
	Type  css_lexer.T
	Value string
	raw   string
}

type cssTokenizers struct {
	// The text this stream tokenizes, its tokens, the index of the next one, and where the last one
	// returned ends.
	src    string
	tokens []css_lexer.Token
	i      int
	end    int32

	// The token `Next` returned last.
	current cssToken

	// The file path of the current file being parsed.
	filePath string

	// The mixin whose expansion this stream is, as `<file path>#<name>`, and its name alone. Empty
	// for the stream of the file being parsed. The key is read by `isExpanding` to refuse
	// re-entering a mixin already open.
	mixinKey  string
	mixinName string
}

type cssTokenizer struct {
	// Stack of tokenizers - one for the file being parsed, plus one for each mixin definition
	// inserted into the stream. The last element is the current one.
	tokenizers []*cssTokenizers

	// Nesting level of the current block.
	nesting int

	incrNestingOnNext bool

	// Set when the stream's own text - not an inserted mixin - held a bad token, which only
	// malformed CSS has. Every token passes through `next`, definition captures included.
	malformed bool

	// An inserted mixin whose end `next` has just returned, still on the stack until the next call.
	exhausted *cssTokenizers

	// How many of the streams on the stack are mixins, not the `}` the parser puts back.
	openMixins int
}

func newCssTokenizer(input string, filePath string) *cssTokenizer {
	return &cssTokenizer{
		tokenizers: []*cssTokenizers{newTokenizer(input, filePath)},
	}
}

// The lexer's own warnings are dropped: esbuild lexes the output again, and reports them then.
var discardLog = logger.Log{AddMsg: func(logger.Msg) {}}

func newTokenizer(input string, filePath string) *cssTokenizers {
	tokens := css_lexer.Tokenize(discardLog, logger.Source{Contents: input}, css_lexer.Options{})

	return &cssTokenizers{src: input, tokens: tokens.Tokens, filePath: filePath}
}

// Returns the next token, and the end of the stream once there are none, for every later call too.
//
// Tokens are copied from the source as written, never written back from their value, so what the
// parser does not replace comes out unchanged. The lexer leaves out a comment that has no
// whitespace beside it, and a byte order mark; the text between two tokens is returned as a
// whitespace token of its own, so that dropping the token after it - a `@define-mixin`, say -
// keeps it.
func (t *cssTokenizers) Next() cssToken {
	start := int32(len(t.src))
	if t.i < len(t.tokens) {
		start = t.tokens[t.i].Range.Loc.Start
	}

	switch {
	case t.end < start:
		raw := t.src[t.end:start]
		t.current = cssToken{Type: css_lexer.TWhitespace, Value: raw, raw: raw}
		t.end = start
	case t.i < len(t.tokens):
		tok := t.tokens[t.i]
		t.i++
		t.end = tok.Range.End()
		t.current = cssToken{Type: tok.Kind, Value: tok.DecodedText(t.src), raw: t.src[start:t.end]}
	default:
		t.current = cssToken{Type: css_lexer.TEndOfFile}
	}

	return t.current
}

// Whether `t` ends the stream.
func endsStream(t css_lexer.T) bool {
	return t == css_lexer.TEndOfFile
}

// A bad string or url, or a backslash before a newline: a newline inside a string or url(), or
// after a backslash. Only malformed CSS has one.
func isBad(t cssToken) bool {
	return t.Type == css_lexer.TUnterminatedString || t.Type == css_lexer.TBadURL ||
		(t.Type == css_lexer.TDelim && t.raw == `\`)
}

func (x *cssTokenizer) next() cssToken {
	// Pop the inserted mixin that ran out last time, if it is still on top. Whatever its end
	// completed - a `@mixin` declaration that was its last statement - can have inserted another
	// above it. It then stays below until that one is done, and runs out again: removed at once,
	// it was gone from cycle detection while the mixin it included expanded, so two mixins
	// including each other never met as a cycle and the parse never ended.
	if x.exhausted != nil {
		if x.tokenizers[len(x.tokenizers)-1] == x.exhausted {
			x.tokenizers = x.tokenizers[:len(x.tokenizers)-1]
			if x.exhausted.mixinName != "" {
				x.openMixins--
			}
		}
		x.exhausted = nil
	}

	token := x.currentTokenizer().Next()
	if isBad(token) && len(x.tokenizers) == 1 {
		x.malformed = true
	}

	// An inserted mixin has run out. Its end is returned, and it stays on the stack until the next
	// call, so whatever was reading - a `@mixin` declaration that is the mixin's last statement,
	// with no semicolon - ends there too and resolves while the mixin is still open to cycle
	// detection. Popping first walked the declaration on into the stream that included the mixin,
	// swallowing what followed, and let `@define-mixin m{@mixin m}` re-insert itself forever.
	// `terminateBody` now gives such a declaration its semicolon when the mixin is defined, so no
	// input reaches this today and no test can. It stays so that a body left unterminated by some
	// future path still ends with its mixin instead of swallowing what follows.
	if endsStream(token.Type) && len(x.tokenizers) > 1 {
		x.exhausted = x.tokenizers[len(x.tokenizers)-1]
		return token
	}

	if x.incrNestingOnNext {
		x.incrNestingOnNext = false
		x.nesting++
	}

	switch token.Type {
	case css_lexer.TOpenBrace:
		x.incrNestingOnNext = true

	case css_lexer.TCloseBrace:
		// A `}` with no block to close leaves the root the root. Counted, it took the nesting below
		// zero, where nothing was at the root again: a later `@define-mixin` captured to the end of
		// the file and everything after it was dropped.
		if x.nesting > 0 {
			x.nesting--
		}
	}

	return token
}

func (x *cssTokenizer) currentTokenizer() *cssTokenizers {
	return x.tokenizers[len(x.tokenizers)-1]
}

func (x *cssTokenizer) currentToken() cssToken {
	return x.currentTokenizer().current
}

// The file path of the stream currently being tokenized.
func (x *cssTokenizer) currentFilePath() string {
	return x.tokenizers[len(x.tokenizers)-1].filePath
}

// Insert the given tokens into the stream: the definition of the mixin `mixinName` from `filePath`,
// or with no name, tokens that are no mixin's.
func (x *cssTokenizer) insertTokens(tokens string, filePath string, mixinName string) {
	t := newTokenizer(tokens, filePath)
	t.mixinName = mixinName
	if mixinName != "" {
		t.mixinKey = filePath + "#" + mixinName
		x.openMixins++
	}

	x.tokenizers = append(x.tokenizers, t)
}

// Whether the given mixin is already open somewhere up the stack, ie. expanding it again would
// be re-entering an expansion still in progress.
func (x *cssTokenizer) isExpanding(mixinKey string) bool {
	for _, t := range x.tokenizers {
		if t.mixinKey == mixinKey {
			return true
		}
	}

	return false
}

// Fetch the mixin definition at the current token, and return its name and definition.
func (x *cssTokenizer) parseMixinDefinition() (string, string) {
	if x.nesting > 0 {
		// @define-mixin must be declared at the root level. Pass it through as is.
		return "", ""
	}

	var mixinIdent string

	// Iterate over all tokens until the next open brace to find the mixin name.
	x.forEachToken(func(token cssToken) bool {
		switch token.Type {
		case css_lexer.TOpenBrace:
			return false

		case css_lexer.TIdent:
			if mixinIdent == "" {
				mixinIdent = token.Value
			}
		}

		return true
	})

	if mixinIdent == "" {
		// No ident found. Ignore it!
		return "", ""
	}

	return mixinIdent, terminateBody(x.captureBlock(0))
}

// A block's last declaration may go without a semicolon, but an inserted mixin body is followed by
// whatever came after its `@mixin`, so `@define-mixin m{color:red}a{@mixin m;color:blue}` became
// `a{color:redcolor:blue}`. The body gets the semicolon it left out. Decided by the body's last
// token other than whitespace, comments, `<!--` and `-->`: a body ending in a rule and then one of
// those is not missing one, and given one it stuck to the next selector at the root. The semicolon
// goes straight after that token, `end` bytes in: trimming the body's trailing whitespace instead
// would take the space of an escape that ends it, `foo\ `, and escape the semicolon.
func terminateBody(body string, last css_lexer.T, end int) string {
	switch last {
	case noToken, css_lexer.TSemicolon, css_lexer.TCloseBrace:
		return body
	}

	return body[:end] + ";" + body[end:]
}

// The type `captureBlock` reports for a block holding nothing but whitespace, comments, `<!--` and
// `-->`. No captured token has this type: `forEachToken` stops at the end of the stream.
const noToken = css_lexer.TEndOfFile

// Capture all output between the nest opening brace, until the closing brace at the given level,
// with the type of its last token other than whitespace, comments, `<!--` and `-->`, none of which
// is a statement, and where in the output that token ends.
func (x *cssTokenizer) captureBlock(level int) (string, css_lexer.T, int) {
	var content strings.Builder
	last := noToken
	end := 0

	x.forEachToken(func(token cssToken) bool {
		if token.Type == css_lexer.TOpenBrace && x.nesting == level {
			content.Reset()
			return true
		}

		if token.Type == css_lexer.TCloseBrace && x.nesting == level {
			return false
		}

		content.WriteString(token.raw)

		switch token.Type {
		case css_lexer.TWhitespace, css_lexer.TCDO, css_lexer.TCDC:
		default:
			last = token.Type
			end = content.Len()
		}

		return true
	})

	return content.String(), last, end
}

// Iterate over all tokens, passing the given iterator function `iterFn` for each iteration.
// Returning false from that function will break from the iteration.
//
// Iteration always stops at the end of the input, so a caller that is waiting for a token which
// never arrives - an unterminated mixin definition, say - terminates instead of spinning on the
// end-of-input token, which the tokenizer returns forever once reached. The "bad" tokens are passed
// to `iterFn` as content.
func (x *cssTokenizer) forEachToken(iterFn func(token cssToken) bool) {
	for {
		token := x.currentToken()
		if endsStream(token.Type) {
			break
		}

		if !iterFn(token) {
			break
		}

		x.next()
	}
}
