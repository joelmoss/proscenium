package types

import "encoding/json"

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
// - OutputDir - Output directory where assets are built or pre-compiled to, relative to the Rails root.
// - Environment - The environment (1 = development, 2 = test, 3 = production)
// - EnvVars - Map of environment variables.
// - RubyGems - Map of bundled ruby gem names and paths.
// - Aliases - Map of aliases.
// - External - Map of external paths - passed directly to esbuild's `external` option.
// - Precompile - Map of glob patterns to precompile.
// - External - List of paths or glob patterns to treat as external.
// - CodeSplitting?
// - Bundle?
// - Debug?
type ConfigT struct {
	RootPath      string
	OutputDir     string
	GemPath       string
	EnvVars       map[string]string
	RubyGems      map[string]string
	Aliases       map[string]string
	External      []string
	Precompile    []string
	Debug         bool
	CodeSplitting bool
	Bundle        bool
	Environment   Environment

	// For testing
	InternalTesting      bool
	UseDevCSSModuleNames bool
}

var Config = ConfigT{CodeSplitting: true, Bundle: true}
var zeroConfig = &ConfigT{
	CodeSplitting: true,
	Bundle:        true,
}

func (config *ConfigT) Reset() {
	*config = *zeroConfig
}

type PluginData = struct {
	IsResolvingPath bool
	ImportedFromJs  bool
	RealPath        string
	GemPath         string
}

func UnmarshalConfig(data []byte) error {
	return json.Unmarshal(data, &Config)
}

// Parses the given JSON into a fresh ConfigT, independent of the shared global Config. Callers
// that don't need the global (eg. concurrent-safe call sites) should prefer this over
// UnmarshalConfig - see the global config refactor plan.
func NewConfig(data []byte) (*ConfigT, error) {
	cfg := &ConfigT{CodeSplitting: true, Bundle: true}
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}

	return cfg, nil
}

// The maximum size of an HTTP response body to cache.
var MaxHttpBodySize int64 = 1024 * 1024 * 1 // 1MB
