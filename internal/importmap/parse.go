package importmap

import (
	"encoding/json"
	"errors"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"
	"reflect"

	"github.com/dop251/goja"
	"github.com/mitchellh/mapstructure"
)

type ContentType uint8

// Holds the parsed content of the import map.
// FIXME: This is cached, which means we have to restart rails to pick up changes to the import map.
var Contents *types.ImportMap = &types.ImportMap{}

const (
	JsonType ContentType = iota + 1
	JavascriptType
)

type SyntaxError struct {
	Message string
}

func (err SyntaxError) Error() string {
	return err.Message
}

func Parse(importMap []byte) error {
	if Contents.IsParsed {
		return nil
	}

	if len(importMap) > 0 {
		err := parseContents(importMap, JsonType)
		if err != nil {
			return errors.New(reflect.TypeOf(err).String() + ": " + err.Error())
		}
	} else if len(types.Config.ImportMapPath) > 0 {
		err := parseFile(path.Join(types.Config.RootPath, types.Config.ImportMapPath))
		if err != nil {
			return err
		}
	}

	return nil
}

// Parses the import map file at the given path, and for the given environment. The file can be a JSON or JS file.
func parseFile(file string) error {
	bytes, err := os.ReadFile(file)
	if err != nil {
		return err
	}

	var contentType ContentType
	switch path.Ext(file) {
	case ".json":
		contentType = JsonType
	case ".js":
		contentType = JavascriptType
	}

	return parseContents(bytes, contentType)
}

// Parses the given import map contents as JSON or JS, and for the given environment.
func parseContents(contents []byte, contentType ContentType) error {
	if contentType == JsonType {
		err := json.Unmarshal(contents, &Contents)
		if err != nil {
			return err
		}
	} else if contentType == JavascriptType {
		vm := goja.New()
		v, runErr := vm.RunString("(" + string(contents) + ")('" + types.Config.Environment.String() + "')")
		if runErr != nil {
			return runErr
		}

		err := mapstructure.Decode(v.Export(), &Contents)
		if err != nil {
			return err
		}
	}

	Contents.IsParsed = true

	return nil
}
