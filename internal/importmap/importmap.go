package importmap

import (
	"encoding/json"
	"errors"
	"fmt"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"

	"github.com/dop251/goja"
	"github.com/mitchellh/mapstructure"
)

type ImportMapScopes map[string]string
type ImportMapImports map[string]string
type contentType uint8

func wrapError(err error) error {
	return fmt.Errorf("Cannot read import map: %w", err)
}

const (
	JsonType contentType = iota
	JavascriptType
	NoType
)

type ImportMap struct {
	Imports  ImportMapImports
	Scopes   map[string]ImportMapScopes
	FilePath string
	IsParsed bool
}

func (ctype contentType) String() string {
	return [...]string{"json", "javascript", "nil"}[ctype]
}

func (im *ImportMap) reset() {
	TEST_IMPORT_MAP_FILE = ""
	TEST_IMPORT_MAP_TYPE = NoType
	im.Imports = map[string]string{}
	im.Scopes = map[string]ImportMapScopes{}
	im.FilePath = "UKNOWN"
	im.IsParsed = false
}

func (im *ImportMap) parse() error {
	if im.IsParsed {
		return nil
	}

	filePath, ctype := im.guessFile()
	if ctype == NoType {
		return nil
	}

	fileContents, err := os.ReadFile(filePath)
	if err != nil {
		return wrapError(err)
	}

	err = im.parseContents(fileContents, ctype)
	if err != nil {
		return err
	}

	return nil
}

// Parses the given import map `contents` as JSON or JS (`contentType`).
func (im *ImportMap) parseContents(contents []byte, contentType contentType) error {
	if contentType == JsonType {
		if err := json.Unmarshal(contents, &im); err != nil {
			return wrapError(err)
		}
	} else if contentType == JavascriptType {
		vm := goja.New()
		jsFn, jsErr := vm.RunString(string(contents))
		if jsErr != nil {
			return wrapError(jsErr)
		}

		mapFn, ok := goja.AssertFunction(jsFn)
		if !ok {
			return wrapError(errors.New("invalid format"))
		}

		fnRes, err := mapFn(goja.Undefined(), vm.ToValue(types.Config.Environment.String()))
		if err != nil {
			return wrapError(err)
		}

		if err = mapstructure.Decode(fnRes.Export(), &im); err != nil {
			return wrapError(err)
		}
	}

	im.IsParsed = true

	return nil
}

var TEST_IMPORT_MAP_FILE string
var TEST_IMPORT_MAP_TYPE contentType

func (im *ImportMap) guessFile() (string, contentType) {
	if TEST_IMPORT_MAP_FILE != "" &&
		(TEST_IMPORT_MAP_TYPE == JsonType || TEST_IMPORT_MAP_TYPE == JavascriptType) {
		if filePath, ok := im.fileExists(TEST_IMPORT_MAP_FILE); ok {
			return filePath, TEST_IMPORT_MAP_TYPE
		} else {
			panic("Cannot find TEST_IMPORT_MAP_FILE: " + TEST_IMPORT_MAP_FILE)
		}
	} else if filePath, ok := im.fileExists("config/import_map.json"); ok {
		return filePath, JsonType
	} else if filePath, ok := im.fileExists("config/import_map.js"); ok {
		return filePath, JavascriptType
	} else {
		return "", NoType
	}
}

func (im *ImportMap) fileExists(file string) (string, bool) {
	filePath := path.Join(types.Config.RootPath, file)

	if _, err := os.Stat(filePath); errors.Is(err, os.ErrNotExist) {
		return "", false
	} else {
		im.FilePath = filePath
		return filePath, true
	}
}

var importmap ImportMap

func Imports() (ImportMapImports, error) {
	if !importmap.IsParsed {
		if err := importmap.parse(); err != nil {
			return nil, err
		}
	}

	return importmap.Imports, nil
}

func FilePath() string {
	return importmap.FilePath
}

// TESTING HELPERS
func NewJavaScriptImportMap(contents []byte) error {
	return NewImportMap(contents, JavascriptType)
}

func NewJsonImportMap(contents []byte) error {
	return NewImportMap(contents, JsonType)
}

func NewImportMap(contents []byte, ctype contentType) error {
	importmap.reset()

	err := importmap.parseContents(contents, ctype)
	if err != nil {
		return err
	}

	return nil
}

func Reset() {
	importmap.reset()
}
