package importmap_test

import (
	"encoding/json"
	"joelmoss/proscenium/golib/importmap"
	"os"
	"path"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParse(t *testing.T) {
	t.Run("invalid json", func(t *testing.T) {
		contents := `{[}]}`
		_, err := importmap.Parse([]byte(contents))

		var syntaxError *json.SyntaxError
		assert.ErrorAs(t, err, &syntaxError)
	})

	t.Run("invalid imports", func(t *testing.T) {
		contents := `{"imports": "as"}`
		_, err := importmap.Parse([]byte(contents))

		var jsonErr *json.UnmarshalTypeError
		assert.ErrorAs(t, err, &jsonErr)
	})

	t.Run("imports", func(t *testing.T) {
		assert := assert.New(t)

		contents := `{
			"imports": {
				"foo": "/lib/foo.js"
			},
			"scopes": {
				"/lib/import_map/": {
					"foo": "/lib/foo4.js"
				}
			}
		}`
		result, _ := importmap.Parse([]byte(contents))

		assert.Equal(map[string]interface{}{"foo": "/lib/foo.js"}, result.Imports)
	})
}

func TestParseFile(t *testing.T) {
	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	assert := assert.New(t)

	file := path.Join(root, "config/import_maps/no_imports.json")
	result, _ := importmap.ParseFile(file)

	assert.Empty(result.Imports)
	assert.Empty(result.Scopes)
}
