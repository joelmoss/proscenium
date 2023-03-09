package importmap

import (
	"encoding/json"
	"os"
)

type ImportMap struct {
	Imports map[string]string
	Scopes  map[string]any
}

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
}
