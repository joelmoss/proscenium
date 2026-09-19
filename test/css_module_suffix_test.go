package proscenium_test

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"

	"github.com/joelmoss/esbuild-internal/ast"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

type cssModuleSuffixRow struct {
	Path   string `json:"path"`
	Hex    string `json:"hex"`
	Suffix string `json:"suffix"`
}

// Reads the table that test/css_module/suffix_test.rb checks Proscenium::Utils.css_module_suffix
// against. A row has a `path`, or a `hex` for a path that is not valid UTF-8 and so cannot be
// written in JSON.
func loadCssModuleSuffixRows() []cssModuleSuffixRow {
	data, err := os.ReadFile("css_module_suffixes.json")
	if err != nil {
		panic(err)
	}

	var rows []cssModuleSuffixRow
	if err := json.Unmarshal(data, &rows); err != nil {
		panic(err)
	}

	return rows
}

// The readable part of a CSS module class name is built here, by `CssLocalAppendice`, for the
// stylesheet and the JS module, and again in Ruby, for the class names a view emits. The two must
// agree byte for byte or the style silently does not apply. If this fails, Go's rule changed:
// update Proscenium::Utils.css_module_suffix in lib/proscenium/utils.rb, then the table.
var _ = Describe("CssLocalAppendice", func() {
	for _, row := range loadCssModuleSuffixRows() {
		path := row.Path
		if row.Hex != "" {
			raw, err := hex.DecodeString(row.Hex)
			if err != nil {
				panic(err)
			}

			path = string(raw)
		}

		It(fmt.Sprintf("gives %q for %q, as Ruby does", row.Suffix, path), func() {
			Expect(ast.CssLocalAppendice(path)).To(Equal(row.Suffix))
		})
	}
})
