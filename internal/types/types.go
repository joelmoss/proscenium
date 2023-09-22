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

var Config struct {
	RootPath      string
	GemPath       string
	Engines       map[string]string
	Debug         bool
	CodeSplitting bool
	Environment   Environment
}

type ImportMapScopes map[string]string

type ImportMap struct {
	Imports  map[string]string
	Scopes   map[string]ImportMapScopes
	IsParsed bool
}

type PluginData = struct {
	IsResolvingPath                bool
	ImportedFromJs                 bool
	CssModuleImportedFromCssModule bool
	CssModuleHash                  string
}

// The maximum size of an HTTP response body to cache.
var MaxHttpBodySize int64 = 1024 * 1024 * 1 // 1MB
