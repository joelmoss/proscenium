package api

type Environment uint8

const (
	DevEnv Environment = iota + 1
	TestEnv
	ProdEnv
)

func (e Environment) String() string {
	return [...]string{"development", "test", "production"}[e-1]
}

type PluginOptions struct {
	ImportMap *ImportMap
}

type ImportMap struct {
	Imports map[string]string
	Scopes  map[string]any
}
