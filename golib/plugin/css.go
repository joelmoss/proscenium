package plugin

import (
	"crypto/sha1"
	"encoding/hex"
	"os"

	esbuild "github.com/evanw/esbuild/pkg/api"
	"github.com/gorilla/css/scanner"

	"github.com/k0kubun/pp/v3"
)

func getSHA1Hash(message string) string {
	hash := sha1.Sum([]byte(message))
	return hex.EncodeToString(hash[:])[0:8]
}

const myMixin string = `color: blue; & h1 {color: pink;} ;font-size: 1em;`

func Css() esbuild.Plugin {
	return esbuild.Plugin{
		Name: "Css",
		Setup: func(build esbuild.PluginBuild) {
			build.OnLoad(esbuild.OnLoadOptions{Filter: `\.css$`},
				func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
					hash := getSHA1Hash(args.Path)

					text, err := os.ReadFile(args.Path)
					if err != nil {
						return esbuild.OnLoadResult{}, err
					}

					pp.Printf(string(text))

					var output string
					classIdent := false
					mixinAtRule := false

					tokens := scanner.New(string(text))
					for {
						token := tokens.Next()

						if token.Type == scanner.TokenEOF || token.Type == scanner.TokenError {
							break
						}

						pp.Println(token.Type.String(), token)

						if mixinAtRule {
							if token.Type == scanner.TokenS {
								continue
							} else if token.Type == scanner.TokenIdent {
								// Find the mixin and append its contents to the output.
								output += myMixin
								continue
							} else if token.Type == scanner.TokenChar && token.Value == ";" {
								mixinAtRule = false
								continue
							}
						}

						if token.Type == scanner.TokenAtKeyword && token.Value == "@mixin" {
							mixinAtRule = true
							continue
						}

						// Rename class identuifier to CSS module identifier
						if token.Type == scanner.TokenChar && token.Value == "." {
							classIdent = true
						} else if classIdent && token.Type == scanner.TokenIdent {
							// Prepend the hash to the class name.
							output += hash

							classIdent = false
						}

						output += token.Value
					}

					return esbuild.OnLoadResult{
						Contents: &output,
						Loader:   esbuild.LoaderCSS,
					}, nil
				})
		},
	}
}
