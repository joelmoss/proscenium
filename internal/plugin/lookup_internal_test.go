package plugin

import (
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"
	"testing"
)

// The lookup policy for a bare import from a gem's file, on a real tree: a home directory holding
// a stray node_modules, an app, and a gem installed outside the app with node_modules of its own.
func TestBareLookupDir(t *testing.T) {
	home := filepath.ToSlash(t.TempDir())
	app := home + "/app"
	gem := home + "/gems/widget"
	mkdirs := func(paths ...string) {
		for _, p := range paths {
			if err := os.MkdirAll(filepath.FromSlash(p), 0o755); err != nil {
				t.Fatal(err)
			}
		}
	}
	mkdirs(
		home+"/node_modules/stray",          // above the gem root: never the gem's
		app+"/node_modules/react",           // the app's own package
		app+"/node_modules/pkg/lib",         // a package the app installed
		gem+"/node_modules/ms",              // the gem's own package, at its root
		gem+"/lib/deep/node_modules/nested", // a package nearer the importer
		gem+"/lib/deep",
	)
	// The importers that IsAppPackageFile evaluates must exist: a path it cannot evaluate counts as
	// an app package anyway, so a missing file would pass that row for the wrong reason.
	for _, f := range []string{app + "/node_modules/pkg/lib/x.js", gem + "/lib/deep/x.js", gem + "/x.js"} {
		if err := os.WriteFile(filepath.FromSlash(f), nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}

	cfg := &types.ConfigT{
		RootPath: app,
		RubyGems: map[string]string{"widget": gem, "mapped": home + "/gems/mapped"},
		DependencyContexts: map[string]string{
			"mapped": app + "/.proscenium/packages/mapped",
		},
	}

	// A gem developed in the app's own repository (`gemspec` in the Gemfile) has the app root as
	// its root (#173), so the packages the app installed are inside it.
	appGem := &types.ConfigT{RootPath: app, RubyGems: map[string]string{"app_gem": app}}

	tests := []struct {
		name, importer, specifier string
		dir, mappedGem            string
		ok                        bool
		cfg                       *types.ConfigT
	}{
		{"a mapped gem resolves from its context", home + "/gems/mapped/index.js", "ms", app + "/.proscenium/packages/mapped", "mapped", true, cfg},
		{"the nearest node_modules holding the package", gem + "/lib/deep/x.js", "nested", gem + "/lib/deep", "", true, cfg},
		{"the gem root's node_modules", gem + "/lib/deep/x.js", "ms/index.js", gem, "", true, cfg},
		{"a scoped name is looked up whole", gem + "/lib/deep/x.js", "@scope/missing/x", app, "", true, cfg},
		{"a package only above the gem root is not the gem's", gem + "/lib/deep/x.js", "stray", app, "", true, cfg},
		{"a package the gem does not have resolves from the app", gem + "/x.js", "react", app, "", true, cfg},
		{"a relative specifier is not a bare import", gem + "/lib/deep/x.js", "./nested", "", "", false, cfg},
		{"a file that is not a gem's keeps its own lookup", app + "/app/views/x.js", "react", "", "", false, cfg},
		{"a package the app installed in a gem's root keeps its own", app + "/node_modules/pkg/lib/x.js", "react", "", "", false, appGem},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir, mappedGem, ok := bareLookupDir(tt.importer, tt.specifier, tt.cfg)
			if dir != tt.dir || mappedGem != tt.mappedGem || ok != tt.ok {
				t.Errorf("bareLookupDir(%q, %q) = (%q, %q, %v), want (%q, %q, %v)",
					tt.importer, tt.specifier, dir, mappedGem, ok, tt.dir, tt.mappedGem, tt.ok)
			}
		})
	}
}
