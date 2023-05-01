package types

type Environment uint8

// The environment (1 = development, 2 = test, 3 = production)
const (
	DevEnv Environment = iota + 1
	TestEnv
	ProdEnv
)

func (e Environment) String() string {
	return [...]string{"development", "test", "production"}[e-1]
}

type ImportMapScopes map[string]string

type ImportMap struct {
	Imports  map[string]string
	Scopes   map[string]ImportMapScopes
	IsParsed bool
}

var Env Environment

type PluginData = struct {
	IsResolvingPath bool
	ImportedFromJs  bool
}

// The maximum size of an HTTP response body to cache.
var MaxHttpBodySize int64 = 1024 * 1024 * 1 // 1MB
