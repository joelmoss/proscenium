package css

import (
	"errors"
	"fmt"
	"joelmoss/proscenium/internal/utils"
	"log"
	"slices"
	"strings"

	"github.com/riking/cssparse/tokenizer"
)

type cssTokenizers struct {
	tokenizer *tokenizer.Tokenizer

	// The file path of the current file being parsed.
	filePath string

	// The mixin whose expansion this stream is, as `<file path>#<name>`. Empty for the stream of
	// the file being parsed. Read by `isExpanding` to refuse re-entering a mixin already open.
	mixinKey string
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
}

func newCssTokenizer(input interface{}, filePath string) (*cssTokenizer, error) {
	inputString, ok := utils.ToString(input)
	if !ok {
		return nil, errors.New("newCssTokenizer: input is not a string")
	}

	tk := cssTokenizers{
		tokenizer: newTokenizer(inputString),
		filePath:  filePath,
	}

	return &cssTokenizer{
		tokenizers: []*cssTokenizers{&tk},
	}, nil
}

// CSS input preprocessing turns CRLF, CR and form feed into LF. The tokenizer does the first two
// and not the form feed, so a form feed ending a hex escape (`.a\2E\fb`, class `a.b`) was kept
// after it and written back as `.a\2E \fb`: class `a.` and a descendant `b`. All three are done
// here, CRLF first, so a CR then a form feed stays two newlines rather than becoming a CRLF the
// tokenizer would fold into one.
var newlines = strings.NewReplacer("\r\n", "\n", "\r", "\n", "\f", "\n")

func newTokenizer(input string) *tokenizer.Tokenizer {
	return tokenizer.NewTokenizer(strings.NewReader(newlines.Replace(input)))
}

// Whether `t` ends the stream. The tokenizer's own StopToken also counts a bad string, url or
// escape, which is recorded as `malformed` instead of ending a mixin stream or a scan early.
func endsStream(t tokenizer.TokenType) bool {
	return t == tokenizer.TokenEOF || t == tokenizer.TokenError
}

// A bad string, url or escape: a newline inside a string or url(), or after a backslash. Only
// malformed CSS has one.
func isBad(t tokenizer.TokenType) bool {
	return t == tokenizer.TokenBadString || t == tokenizer.TokenBadURI || t == tokenizer.TokenBadEscape
}

// The token as CSS text. The tokenizer decodes `\c ` in a string into a literal form feed and writes
// it back raw, which CSS reads as a newline, ending the string: a captured mixin holding one came out
// broken. Written back as the escape.
func render(t *tokenizer.Token) string {
	return strings.ReplaceAll(t.Render(), "\f", `\c `)
}

func (x *cssTokenizer) next() *tokenizer.Token {
	// Pop the inserted mixin that ran out last time. It may no longer be on top: whatever its end
	// completed - a `@mixin` declaration that was its last statement - can have inserted another.
	if x.exhausted != nil {
		x.tokenizers = slices.DeleteFunc(x.tokenizers, func(t *cssTokenizers) bool { return t == x.exhausted })
		x.exhausted = nil
	}

	token := x.currentTokenizer().Next()
	if isBad(token.Type) && len(x.tokenizers) == 1 {
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
		return &token
	}

	if x.incrNestingOnNext {
		x.incrNestingOnNext = false
		x.nesting++
	}

	switch token.Type {
	case tokenizer.TokenOpenBrace:
		x.incrNestingOnNext = true

	case tokenizer.TokenCloseBrace:
		x.nesting--
	}

	x.logToken()

	return &token
}

func (x *cssTokenizer) currentTokenizer() *tokenizer.Tokenizer {
	return x.tokenizers[len(x.tokenizers)-1].tokenizer
}

func (x *cssTokenizer) currentToken() tokenizer.Token {
	return x.currentTokenizer().Token()
}

// The file path of the stream currently being tokenized.
func (x *cssTokenizer) currentFilePath() string {
	return x.tokenizers[len(x.tokenizers)-1].filePath
}

func (x *cssTokenizer) insertTokens(tokens string, filePath string, mixinKey string) {
	x.tokenizers = append(x.tokenizers, &cssTokenizers{
		tokenizer: newTokenizer(tokens),
		filePath:  filePath,
		mixinKey:  mixinKey,
	})
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
	var original strings.Builder

	// Iterate over all tokens until the next open brace to find the mixin name.
	x.forEachToken(func(token *tokenizer.Token) bool {
		original.WriteString(render(token))

		switch token.Type {
		case tokenizer.TokenOpenBrace:
			return false

		case tokenizer.TokenIdent:
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
// token other than whitespace and comments: a body ending in a rule and then a comment, `<!--` or
// `-->` is not missing one, and given one it stuck to the next selector at the root.
func terminateBody(body string, last tokenizer.TokenType) string {
	switch last {
	case noToken, tokenizer.TokenSemicolon, tokenizer.TokenCloseBrace, tokenizer.TokenCDO, tokenizer.TokenCDC:
		return body
	}

	end := len(strings.TrimRight(body, " \t\r\n\f"))

	return body[:end] + ";" + body[end:]
}

// The type `captureBlock` reports for a block holding nothing but whitespace and comments. No
// captured token has this type: `forEachToken` stops at TokenError, which `endsStream` counts.
const noToken = tokenizer.TokenError

// Capture all output between the nest opening brace, until the closing brace at the given level,
// and the type of its last token other than whitespace and comments.
func (x *cssTokenizer) captureBlock(level int) (string, tokenizer.TokenType) {
	var content strings.Builder
	last := noToken

	x.forEachToken(func(token *tokenizer.Token) bool {
		if token.Type == tokenizer.TokenOpenBrace && x.nesting == level {
			content.Reset()
			return true
		}

		if token.Type == tokenizer.TokenCloseBrace && x.nesting == level {
			return false
		}

		if token.Type != tokenizer.TokenS && token.Type != tokenizer.TokenComment {
			last = token.Type
		}

		content.WriteString(render(token))
		return true
	})

	return content.String(), last
}

// Iterate over all tokens, passing the given iterator function `iterFn` for each iteration.
// Returning false from that function will break from the iteration.
//
// Iteration always stops at the end of the input, so a caller that is waiting for a token which
// never arrives - an unterminated mixin definition, say - terminates instead of spinning on the
// end-of-input token, which the tokenizer returns forever once reached. An error token is the
// same - the tokenizer consumes nothing more once in error - so it stops too. The "bad" tokens are
// passed to `iterFn` as content.
func (x *cssTokenizer) forEachToken(iterFn func(token *tokenizer.Token) bool) {
	for {
		token := x.currentToken()
		if endsStream(token.Type) {
			break
		}

		if !iterFn(&token) {
			break
		}

		x.next()
	}
}

func (x *cssTokenizer) logOutput(output string) {
	if !debug {
		return
	}

	indent := strings.Repeat("..", x.nesting)
	if indent != "" {
		indent += " "
	}

	log.Printf(" %s> %#v", indent, fmt.Sprint(output))
}

func (x *cssTokenizer) logToken() {
	if !debug {
		return
	}

	indent := strings.Repeat("..", x.nesting)
	if indent != "" {
		indent += " "
	}

	token := x.currentToken()
	log.Printf(" %s  [%s] %#v (p:%v)", indent, token.Type.String(), token.Value, len(x.tokenizers)-1)
}
