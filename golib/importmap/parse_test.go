package importmap_test

import (
	"encoding/json"
	"joelmoss/proscenium/golib/importmap"
	"joelmoss/proscenium/golib/internal"
	"os"
	"path"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParse(t *testing.T) {
	t.Run("invalid json", func(t *testing.T) {
		contents := `{[}]}`
		_, err := importmap.Parse([]byte(contents), importmap.JsonType, internal.TestEnv)

		var syntaxError *json.SyntaxError
		assert.ErrorAs(t, err, &syntaxError)
	})

	t.Run("invalid imports", func(t *testing.T) {
		contents := `{"imports": "as"}`
		_, err := importmap.Parse([]byte(contents), importmap.JsonType, internal.TestEnv)

		var jsonErr *json.UnmarshalTypeError
		assert.ErrorAs(t, err, &jsonErr)
	})

	t.Run("javascript", func(t *testing.T) {
		assert := assert.New(t)

		result, _ := importmap.Parse([]byte(`env => ({
			"imports": {
				"foo": env === 'test' ? "/lib/foo_test.js" : "/lib/foo.js"
			}
		})`), importmap.JavascriptType, internal.TestEnv)

		assert.Equal(map[string]string{"foo": "/lib/foo_test.js"}, result.Imports)
	})

	t.Run("imports", func(t *testing.T) {
		assert := assert.New(t)

		contents := `{
			"imports": {
				"foo": "/lib/foo.js"
			}
		}`
		result, _ := importmap.Parse([]byte(contents), importmap.JsonType, internal.TestEnv)

		assert.Equal(map[string]string{"foo": "/lib/foo.js"}, result.Imports)
	})

	t.Run("scopes", func(t *testing.T) {
		contents := `{
			"imports": {},
			"scopes": {
				"/lib/import_map/": {
					"foo": "/lib/foo4.js"
				}
			}
		}`
		result, _ := importmap.Parse([]byte(contents), importmap.JsonType, internal.TestEnv)

		assert.Equal(t, map[string]internal.ImportMapScopes(map[string]internal.ImportMapScopes{"/lib/import_map/": {"foo": "/lib/foo4.js"}}), result.Scopes)
	})
}

func TestParseFile(t *testing.T) {
	var cwd, _ = os.Getwd()
	var root string = path.Join(cwd, "../../", "test", "internal")

	assert := assert.New(t)

	file := path.Join(root, "config/import_maps/no_imports.json")
	result, _ := importmap.ParseFile(file, internal.TestEnv)

	assert.Empty(result.Imports)
	assert.Empty(result.Scopes)
}
