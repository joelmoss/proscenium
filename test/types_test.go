package proscenium_test

import (
	"encoding/json"
	"joelmoss/proscenium/internal/types"
	"strings"
	"testing"
)

func TestNewConfig(t *testing.T) {
	t.Run("defaults CodeSplitting and Bundle to true", func(t *testing.T) {
		cfg, err := types.NewConfig([]byte(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		if !cfg.CodeSplitting || !cfg.Bundle {
			t.Errorf("expected CodeSplitting and Bundle to default true, got %+v", cfg)
		}
	})

	t.Run("parses provided fields", func(t *testing.T) {
		data, _ := json.Marshal(map[string]any{
			"RootPath":    "/some/path",
			"Environment": 3,
			"Bundle":      false,
		})

		cfg, err := types.NewConfig(data)
		if err != nil {
			t.Fatal(err)
		}
		if cfg.RootPath != "/some/path" {
			t.Errorf("expected RootPath %q, got %q", "/some/path", cfg.RootPath)
		}
		if cfg.Environment != types.ProdEnv {
			t.Errorf("expected Environment %v, got %v", types.ProdEnv, cfg.Environment)
		}
		if cfg.Bundle {
			t.Error("expected Bundle to be false")
		}
	})

	t.Run("defaults a missing Environment to test", func(t *testing.T) {
		cfg, err := types.NewConfig([]byte(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		if cfg.Environment != types.TestEnv {
			t.Errorf("expected Environment %v, got %v", types.TestEnv, cfg.Environment)
		}
	})

	t.Run("refuses an Environment outside 1-3", func(t *testing.T) {
		for data, want := range map[string]string{`{"Environment":0}`: "got 0", `{"Environment":4}`: "got 4"} {
			_, err := types.NewConfig([]byte(data))
			if err == nil || !strings.Contains(err.Error(), want) {
				t.Errorf("expected an error containing %q for %s, got %v", want, data, err)
			}
		}

		if cfg, err := types.NewConfig([]byte(`{"Environment":1}`)); err != nil || cfg.Environment != types.DevEnv {
			t.Errorf("expected Environment 1 to be accepted as development, got %v, %v", cfg, err)
		}
	})

	t.Run("returns the json error on invalid input", func(t *testing.T) {
		_, err := types.NewConfig([]byte(`not json`))
		if err == nil {
			t.Error("expected an error for invalid JSON, got nil")
		}
	})
}

// Every plugin used to assert `args.PluginData.(types.PluginData)` bare, and a gem stylesheet's
// imports arrive with nil - so the assertion panicked. The accessor answers the zero value for
// anything that is not plugin data.
func TestPluginDataOf(t *testing.T) {
	t.Run("nil is the zero value", func(t *testing.T) {
		if got := types.PluginDataOf(nil); got != (types.PluginData{}) {
			t.Errorf("expected the zero value, got %+v", got)
		}
	})

	t.Run("plugin data is returned as is", func(t *testing.T) {
		want := types.PluginData{IsResolvingPath: true, GemPath: "/gems/foo"}
		if got := types.PluginDataOf(want); got != want {
			t.Errorf("expected %+v, got %+v", want, got)
		}
	})

	t.Run("anything else is the zero value", func(t *testing.T) {
		if got := types.PluginDataOf([]byte("replacement contents")); got != (types.PluginData{}) {
			t.Errorf("expected the zero value for a []byte, got %+v", got)
		}
	})
}

func TestShouldMinify(t *testing.T) {
	t.Run("derives from the environment", func(t *testing.T) {
		if (&types.ConfigT{Environment: types.ProdEnv}).ShouldMinify() != true {
			t.Error("expected production to minify")
		}
		if (&types.ConfigT{Environment: types.DevEnv}).ShouldMinify() != false {
			t.Error("expected development not to minify")
		}
		if (&types.ConfigT{Environment: types.TestEnv}).ShouldMinify() != false {
			t.Error("expected test not to minify - a minified stack trace is unreadable")
		}
		if (&types.ConfigT{Environment: types.ProdEnv, Debug: true}).ShouldMinify() != false {
			t.Error("expected Debug to disable minification")
		}
		if (&types.ConfigT{Environment: types.ProdEnv, InternalTesting: true}).ShouldMinify() != false {
			t.Error("expected InternalTesting to disable minification")
		}
	})
}

func TestShouldWrite(t *testing.T) {
	no := false

	t.Run("writes by default", func(t *testing.T) {
		if !(&types.ConfigT{}).ShouldWrite() {
			t.Error("expected ShouldWrite to default true")
		}
	})

	t.Run("an explicit Write=false turns it off", func(t *testing.T) {
		if (&types.ConfigT{Write: &no}).ShouldWrite() {
			t.Error("expected ShouldWrite to be false")
		}
	})

	t.Run("Write round-trips through JSON", func(t *testing.T) {
		cfg, err := types.NewConfig([]byte(`{"Write":false}`))
		if err != nil {
			t.Fatal(err)
		}
		if cfg.Write == nil || *cfg.Write {
			t.Errorf("expected Write to parse as false, got %v", cfg.Write)
		}
	})
}

func TestEnvironmentString(t *testing.T) {
	cases := map[types.Environment]string{
		types.DevEnv: "development", types.TestEnv: "test", types.ProdEnv: "production",
		0: "Environment(0)", 4: "Environment(4)",
	}
	for env, want := range cases {
		if got := env.String(); got != want {
			t.Errorf("Environment(%d).String() = %q, want %q", uint8(env), got, want)
		}
	}
}
