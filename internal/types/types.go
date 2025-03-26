package types

var Debug = false

const RubyGemsScope = "@rubygems/"

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
// - EnvVars - Map of environment variables.
// - RubyGems - Map of bundle ruby gem names and paths.
// - CodeSplitting?
// - ExternalNodeModules? - externalise everything under /node_modules/
// - Bundle?
// - Debug?
type ConfigT struct {
	RootPath            string
	GemPath             string
	EnvVars             map[string]string
	RubyGems            map[string]string
	Debug               bool
	CodeSplitting       bool
	Bundle              bool
	ExternalNodeModules bool
	Environment         Environment

	// For testing
	UseDevCSSModuleNames bool
}

var Config = ConfigT{CodeSplitting: true, Bundle: true}
var zeroConfig = &ConfigT{CodeSplitting: true, Bundle: true}

func (config *ConfigT) Reset() {
	*config = *zeroConfig
}

type PluginData = struct {
	IsResolvingPath bool
	ImportedFromJs  bool
	RealPath        string
	GemPath         string
}

// The maximum size of an HTTP response body to cache.
var MaxHttpBodySize int64 = 1024 * 1024 * 1 // 1MB
