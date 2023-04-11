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
}

type cssTokenizer struct {
	tokenizers []*cssTokenizers

	// Position of the current tokenizer in the tokenizers slice.
	position int

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

	if token.Type.StopToken() {
		if x.position > 0 {
			x.position--
			token = x.currentTokenizer().Next()
		}
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
	return x.tokenizers[x.position].tokenizer
}

func (x *cssTokenizer) currentToken() tokenizer.Token {
	return x.currentTokenizer().Token()
}

func (x *cssTokenizer) insertTokens(tokens string, filePath string) {
	x.tokenizers = append(x.tokenizers, &cssTokenizers{
		tokenizer: tokenizer.NewTokenizer(strings.NewReader(tokens)),
		filePath:  filePath,
	})
	x.position++
}

// Fetch the mixin definition at the current token, and return its name and definition.
func (x *cssTokenizer) parseMixinDefinition() (string, string) {
	if x.nesting > 0 {
		// @define-mixin must be declared at the root level. Pass it through as is.
		return "", ""
	}

	var mixinIdent, original string

	// Iterate over all tokens until the next open brace to find the mixin name.
	x.forEachToken(func(token *tokenizer.Token) bool {
		original += token.Render()

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
	var content string

	x.forEachToken(func(token *tokenizer.Token) bool {
		if token.Type == tokenizer.TokenOpenBrace && x.nesting == level {
			content = ""
			return true
		}

		if token.Type == tokenizer.TokenCloseBrace && x.nesting == level {
			return false
		}

		content += token.Render()
		return true
	})

	return content
}

// Iterate over all tokens, passing the given iterator function `iterFn` for each iteration.
// Returning false from that function will break from the iteration.
func (x *cssTokenizer) forEachToken(iterFn func(token *tokenizer.Token) bool) {
	for {
		token := x.currentToken()
		iterResult := iterFn(&token)
		if !iterResult {
			break
		}

		x.next()
	}
}

func (x *cssTokenizer) log(msg string, args ...interface{}) {
	if !debug {
		return
	}

	indent := strings.Repeat("..", x.nesting)
	if indent != "" {
		indent += " "
	}

	log.Printf("!%s%s", indent, fmt.Sprintf(msg, args...))
}

func (x *cssTokenizer) logToken(args ...interface{}) {
	if !debug {
		return
	}

	indent := strings.Repeat("..", x.nesting)
	if indent != "" {
		indent += " "
	}

	if len(args) > 0 {
		token := args[0].(tokenizer.Token)
		log.Printf("!%s%s %#v (p:%v, n:%v)", indent, token.Type.String(), token.Value, x.position, x.nesting)
	} else {
		token := x.currentToken()
		log.Printf(" %s%s %#v (p:%v, n:%v)", indent, token.Type.String(), token.Value, x.position, x.nesting)
	}
}
