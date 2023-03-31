package css

import (
	"crypto/sha1"
	"encoding/hex"
	"os"
	"strings"

	"github.com/gorilla/css/scanner"
)

func getSHA1Hash(message string) string {
	hash := sha1.Sum([]byte(message))
	return hex.EncodeToString(hash[:])[0:8]
}

// const myMixin string = `color: blue; & h1 {color: pink;} ;font-size: 1em;`

func ParseCssFile(path string) (string, error) {
	input, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return ParseCss(string(input), path)
}

func ParseCss(input string, path string) (string, error) {
	hash := getSHA1Hash(path)

	isModule := false
	if strings.HasSuffix(path, ".module.css") {
		isModule = true
	}

	var output string

	// Count of number of nesting levels, which is essentially just the count of each opening curly
	// brace `{`.
	var nestedLevels int

	// The level at which the global rule is defined.
	var globalLevel int

	// mixinAtRule := false

	tokens := scanner.New(input)

	// Returns the next token, or nil if the end or an error is reached.
	nextToken := func() *scanner.Token {
		token := tokens.Next()

		if token.Type == scanner.TokenEOF || token.Type == scanner.TokenError {
			return nil
		}

		if token.Type == scanner.TokenChar {
			if token.Value == "{" {
				nestedLevels++
			} else if token.Value == "}" {
				nestedLevels--

				if nestedLevels < globalLevel {
					globalLevel = 0
				}
			}
		}

		// pp.Println(token.Type.String(), token, nestedLevels, globalLevel)

		return token
	}

	// Iterate over all tokens until we find a token matching `value`. Returns the matching token and
	// all tokens until that point.
	outputUntilValue := func(value string) (*scanner.Token, []*scanner.Token) {
		var tokensUntil []*scanner.Token

		for {
			token := nextToken()

			if token == nil || token.Value == value {
				return token, tokensUntil
			}

			tokensUntil = append(tokensUntil, token)
			output += token.Value
		}
	}

	// Handle the next token and return the output and whether we should continue.
	handleNextToken := func() (string, bool) {
		token := nextToken()

		if token == nil {
			return "", false
		}

		switch token.Type {

		case scanner.TokenChar:
			if isModule {
				if token.Value == "." {
					nextT := nextToken()

					if nextT.Type == scanner.TokenIdent {
						// Return the unhashed class if we are in a global rule.
						if globalLevel > 0 {
							return "." + nextT.Value, true
						}

						return "." + nextT.Value + hash, true
					}
				} else if token.Value == ":" {
					nextT := nextToken()

					if nextT.Type == scanner.TokenFunction && nextT.Value == "global(" {
						untilV, _ := outputUntilValue(")")
						if untilV == nil {
							return "", false
						}

						token = nextToken()
					} else if nextT.Type == scanner.TokenIdent && nextT.Value == "global" {
						untilV, tokensUntil := outputUntilValue("{")
						if untilV == nil {
							return "", false
						}

						// A class ident may not be present for the global rule, so we need to check for one. If
						// none is found we treat all children as global.
						containsClass := func() bool {
							for _, t := range tokensUntil {
								if t.Type == scanner.TokenChar && t.Value == "." {
									return true
								}
							}
							return false
						}

						if !containsClass() {
							// No class is present, all children are global.
							globalLevel = nestedLevels
						}

						token = nextToken()
					} else {
						return token.Value + nextT.Value, true
					}
				}
			}
		}

		// if mixinAtRule {
		// 	if token.Type == scanner.TokenS {
		// 		continue
		// 	} else if token.Type == scanner.TokenIdent {
		// 		// Find the mixin and append its contents to the output.
		// 		output += myMixin
		// 		continue
		// 	} else if token.Type == scanner.TokenChar && token.Value == ";" {
		// 		mixinAtRule = false
		// 		continue
		// 	}
		// }

		// if token.Type == scanner.TokenAtKeyword && token.Value == "@mixin" {
		// 	mixinAtRule = true
		// 	continue
		// }

		return token.Value, true
	}

	for {
		result, ok := handleNextToken()
		if !ok {
			break
		}

		output += result
	}

	return output, nil
}
