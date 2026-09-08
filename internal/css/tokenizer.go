package css

import (
	"errors"
	"fmt"
	"joelmoss/proscenium/internal/utils"
	"log"
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
}

func newCssTokenizer(input interface{}, filePath string) (*cssTokenizer, error) {
	inputString, ok := utils.ToString(input)
	if !ok {
		return nil, errors.New("newCssTokenizer: input is not a string")
	}

	tk := cssTokenizers{
		tokenizer: tokenizer.NewTokenizer(strings.NewReader(inputString)),
		filePath:  filePath,
	}

	return &cssTokenizer{
		tokenizers: []*cssTokenizers{&tk},
	}, nil
}

func (x *cssTokenizer) next() *tokenizer.Token {
	token := x.currentTokenizer().Next()

	// An inserted mixin definition has run out, so pop back to the stream that included it.
	if token.Type.StopToken() && len(x.tokenizers) > 1 {
		x.tokenizers = x.tokenizers[:len(x.tokenizers)-1]
		return x.next()
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
		tokenizer: tokenizer.NewTokenizer(strings.NewReader(tokens)),
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
		original.WriteString(token.Render())

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

	return mixinIdent, x.captureBlock(0)
}

// Capture all output between the nest opening brace, until the closing brace at the given level.
func (x *cssTokenizer) captureBlock(level int) string {
	var content strings.Builder

	x.forEachToken(func(token *tokenizer.Token) bool {
		if token.Type == tokenizer.TokenOpenBrace && x.nesting == level {
			content.Reset()
			return true
		}

		if token.Type == tokenizer.TokenCloseBrace && x.nesting == level {
			return false
		}

		content.WriteString(token.Render())
		return true
	})

	return content.String()
}

// Iterate over all tokens, passing the given iterator function `iterFn` for each iteration.
// Returning false from that function will break from the iteration.
//
// Iteration always stops at the end of the input, so a caller that is waiting for a token which
// never arrives - an unterminated mixin definition, say - terminates instead of spinning on the
// end-of-input token, which the tokenizer returns forever once reached. Only the end of input stops
// it: the error and "bad" tokens are passed to `iterFn` as content, as they always have been.
func (x *cssTokenizer) forEachToken(iterFn func(token *tokenizer.Token) bool) {
	for {
		token := x.currentToken()
		if token.Type == tokenizer.TokenEOF {
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
