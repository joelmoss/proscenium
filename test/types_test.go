package proscenium_test

import (
	"encoding/json"
	"joelmoss/proscenium/internal/types"
	"testing"
)

func TestNewConfig(t *testing.T) {
	t.Run("defaults match the global Config's defaults", func(t *testing.T) {
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

	t.Run("does not touch the shared global Config", func(t *testing.T) {
		types.Config.Reset()
		types.Config.RootPath = "/original"

		_, err := types.NewConfig([]byte(`{"RootPath": "/different"}`))
		if err != nil {
			t.Fatal(err)
		}

		if types.Config.RootPath != "/original" {
			t.Errorf("NewConfig mutated the global Config: RootPath is now %q", types.Config.RootPath)
		}
	})

	t.Run("returns the json error on invalid input", func(t *testing.T) {
		_, err := types.NewConfig([]byte(`not json`))
		if err == nil {
			t.Error("expected an error for invalid JSON, got nil")
		}
	})
}
