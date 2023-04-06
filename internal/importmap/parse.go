package importmap

import (
	"encoding/json"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"

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

	return Parse(bytes, contentType, env)
}

func Parse(contents []byte, contentType ContentType, env types.Environment) (*types.ImportMap, error) {
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
