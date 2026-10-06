package types

import (
	"encoding/json"
	"fmt"
)

const RubyGemsScope = "@rubygems/"

type Environment uint8

// The environment (1 = development, 2 = test, 3 = production)
const (
	DevEnv Environment = iota + 1
	TestEnv
	ProdEnv
)

// An out-of-range value prints as Environment(N) rather than panicking: indexing a name table by
// e-1 underflowed on the zero value, which a ConfigT built without an Environment carries.
func (e Environment) String() string {
	switch e {
	case DevEnv:
		return "development"
	case TestEnv:
		return "test"
	case ProdEnv:
		return "production"
	}

	return fmt.Sprintf("Environment(%d)", uint8(e))
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

	// Gem dependency contexts (#154): a participating gem's name to the absolute path of its
	// context, `.proscenium/packages/<gem>`. A bare import from a mapped gem resolves from the
	// context alone. Empty until the app adopts them.
	DependencyContexts map[string]string

	// The names of the app's own `link:`, `file:` and workspace dependencies, from its package.json.
	// They keep their link paths when dependency contexts make other packages real-path.
	AppLocalPackages []string
}

type PluginData = struct {
	IsResolvingPath bool
	ImportedFromJs  bool
	RealPath        string
	GemPath         string
}

// The plugin data on a resolve or load argument, or the zero value when there is none. Every
// plugin used to assert `args.PluginData.(PluginData)` bare, which panics on nil - and a gem
// stylesheet's imports arrived with nil, because the css plugin's OnLoad did not carry the data
// bundless had attached. Zero means "no gem, not resolving, not imported from JS", which is what
// each caller falls through to anyway.
func PluginDataOf(v any) PluginData {
	pd, _ := v.(PluginData)

	return pd
}

// Parses the given JSON into a fresh ConfigT. Every FFI call parses its own, so concurrent calls
// share no config state.
// A missing Environment means test, the same fallback Ruby uses for an environment it does not
// recognise (builder.rb). One outside 1-3 is refused rather than built with an unknown name.
func NewConfig(data []byte) (*ConfigT, error) {
	cfg := &ConfigT{CodeSplitting: true, Bundle: true, Environment: TestEnv}
	if err := json.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	if cfg.Environment < DevEnv || cfg.Environment > ProdEnv {
		return nil, fmt.Errorf("config Environment must be 1, 2 or 3, got %d", uint8(cfg.Environment))
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
