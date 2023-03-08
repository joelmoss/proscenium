package importmap

import (
	"encoding/json"
	"os"
)

type (
	Specifier struct {
		Key     string
		Address string
	}

	Scope struct {
		Prefix     string
		Specifiers []*Specifier
	}

	ImportMap struct {
		Imports map[string]interface{}
		Scopes  map[string]any
	}
)

type SyntaxError struct {
	Message string
}

func (err SyntaxError) Error() string {
	return err.Message
}

func ParseFile(file string) (*ImportMap, error) {
	bytes, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}

	return Parse(bytes)
}

func Parse(contents []byte) (*ImportMap, error) {
	var data *ImportMap

	err := json.Unmarshal(contents, &data)
	if err != nil {
		return nil, err
	}

	return data, nil

	// importMap := &ImportMap{}

	// if _, ok = entries["imports"]; ok {
	// 	imports, ok := entries["imports"].(map[string]interface{})
	// 	if !ok {
	// 		return nil, SyntaxError{
	// 			Message: `"imports" must be an object`,
	// 		}
	// 	}

	// 	for key, value := range imports {
	// 		specifier := &Specifier{Key: key}

	// 		switch value := value.(type) {
	// 		case string:
	// 			specifier.Address = value

	// 		default:
	// 			return nil, SyntaxError{
	// 				Message: `specifier address must be a string`,
	// 			}
	// 		}

	// 		importMap.Imports = append(importMap.Imports, specifier)
	// 	}
	// }

	// // e, ok = entries["scopes"]
	// // pp.Print(e, ok)
	// // if ok {
	// // 	scopes, ok := entries["scopes"].(map[string]interface{})
	// // }

	// return importMap, nil
}
