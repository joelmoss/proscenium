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

func Parse(importMap []byte, importMapPath string, root string, env types.Environment) (*types.ImportMap, error) {
	if len(importMap) > 0 {
		imap, err := ParseContents(importMap, JsonType, env)
		if err != nil {
			return nil, errors.New(reflect.TypeOf(err).String() + ": " + err.Error())
		}

		return imap, nil
	} else if len(importMapPath) > 0 {
		imap, err := ParseFile(path.Join(root, importMapPath), env)
		if err != nil {
			return nil, err
		}

		return imap, nil
	}

	return nil, nil
}

// Parses the import map file at the given path, and for the given environment. The file can be a JSON or JS file.
func ParseFile(file string, env types.Environment) (*types.ImportMap, error) {
	bytes, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}

	var contentType ContentType
	switch path.Ext(file) {
	case ".json":
		contentType = JsonType
	case ".js":
		contentType = JavascriptType
	}

	return ParseContents(bytes, contentType, env)
}

// Parses the given import map contents as JSON or JS, and for the given environment.
func ParseContents(contents []byte, contentType ContentType, env types.Environment) (*types.ImportMap, error) {
	var data *types.ImportMap

	if contentType == JsonType {
		err := json.Unmarshal(contents, &data)
		if err != nil {
			return nil, err
		}
	} else if contentType == JavascriptType {
		vm := goja.New()
		v, runErr := vm.RunString("(" + string(contents) + ")('" + env.String() + "')")
		if runErr != nil {
			return nil, runErr
		}

		err := mapstructure.Decode(v.Export(), &data)
		if err != nil {
			return nil, err
		}
	}

	return data, nil
}
