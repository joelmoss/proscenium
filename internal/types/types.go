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

// - RootPath - The working directory, usually Rails root.
// - GemPath - Proscenium gem root.
// - Environment - The environment (1 = development, 2 = test, 3 = production)
// - ImportMapPath - Path to the import map relative to `root`.
// - EnvVars - Map of environment variables.
// - Engines- Map of Rails engine names and paths.
// - CodeSpitting?
// - Debug?
type ConfigT struct {
	RootPath      string
	GemPath       string
	ImportMapPath string
	Engines       map[string]string
	EnvVars       map[string]string
	Debug         bool
	CodeSplitting bool
	Environment   Environment
}

var Config = ConfigT{}
var zeroConfig = &ConfigT{}

func (config *ConfigT) Reset() {
	*config = *zeroConfig
}

type ImportMapScopes map[string]string

type ImportMap struct {
	Imports  map[string]string
	Scopes   map[string]ImportMapScopes
	IsParsed bool
}

type PluginData = struct {
	IsResolvingPath bool
	ImportedFromJs  bool
}

// The maximum size of an HTTP response body to cache.
var MaxHttpBodySize int64 = 1024 * 1024 * 1 // 1MB
