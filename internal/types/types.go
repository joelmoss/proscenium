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
// - Write - Override whether esbuild writes output files to disk. Nil means write, as before.
// - SourcemapInline - Embed the source map in the output rather than emitting a second file.
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

	// Embed the source map as a data URL comment at the end of the output rather than emitting it
	// as a second output file. Off by default: a browser wants the separate `.map` it can fetch on
	// demand. A caller reading the result as a string wants it inline, because fetching the map
	// separately means building the whole module a second time.
	//
	// Read by `build` (and so by BuildToString) only. `Compile` writes its output for a browser to
	// fetch, so it always emits a linked map and ignores this.
	SourcemapInline bool

	// A pointer so that an absent JSON key keeps the default (write), and an explicit `false` is
	// distinguishable from "not set".
	Write *bool

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

// Whether output should be minified. One definition, rather than the same expression repeated at
// every build site.
//
// Production only. Minified output is unreadable in a stack trace - a one-letter function name and
// a column on line 1 - which is the wrong trade anywhere the point is to find out what broke.
// Anything Rails does not recognise as an environment arrives here as TestEnv (builder.rb), so an
// unnamed environment gets readable output too.
//
// Importer#import applies the same rule when it builds a CSS module class name, and the two have
// to agree: unminified identifiers carry a path-derived suffix, so a mismatch means the helper
// renders a class the stylesheet does not define.
func (config *ConfigT) ShouldMinify() bool {
	return !config.InternalTesting && !config.Debug && config.Environment == ProdEnv
}

// Whether esbuild writes its output files to OutputDir. It does by default, even though
// BuildToString only ever reads the in-memory result, so a caller that just wants the string can
// turn it off. OutputFiles is populated either way.
func (config *ConfigT) ShouldWrite() bool {
	if config.Write != nil {
		return *config.Write
	}

	return true
}
