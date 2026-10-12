package plugin

import (
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// The lookup policy for a bare import from a gem's file, on a real tree: a home directory holding
// a stray node_modules, an app, and a gem installed outside the app with node_modules of its own.
func TestBareLookupDirs(t *testing.T) {
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
		gem+"/node_modules/ms/lib", // a package the gem ships, whose files resolve beside themselves
		gem+"/node_modules/react",  // the gem's own copy of a peer, as pnpm installs one
	)
	// The gem leaves React to the app.
	if err := os.WriteFile(filepath.FromSlash(gem+"/package.json"),
		[]byte(`{"name":"widget","peerDependencies":{"react":"^18"}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	// The importers that IsAppPackageFile evaluates must exist: a path it cannot evaluate counts as
	// an app package anyway, so a missing file would pass that row for the wrong reason.
	for _, f := range []string{app + "/node_modules/pkg/lib/x.js", gem + "/lib/deep/x.js", gem + "/x.js",
		gem + "/node_modules/ms/lib/x.js", gem + "/node_modules/tiny.js"} {
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
		dirs                      []string
		mappedGem                 string
		cfg                       *types.ConfigT
	}{
		{"a mapped gem resolves from its context", home + "/gems/mapped/index.js", "ms", []string{app + "/.proscenium/packages/mapped"}, "mapped", cfg},
		{"the nearest node_modules holding the package", gem + "/lib/deep/x.js", "nested", []string{gem + "/lib/deep"}, "", cfg},
		{"the gem root's node_modules", gem + "/lib/deep/x.js", "ms/index.js", []string{gem}, "", cfg},
		{"a file module in node_modules counts", gem + "/lib/deep/x.js", "tiny", []string{gem}, "", cfg},
		{"a scoped name is looked up whole", gem + "/lib/deep/x.js", "@scope/missing/x", []string{app}, "", cfg},
		{"a package only above the gem root is not the gem's", gem + "/lib/deep/x.js", "stray", []string{app}, "", cfg},
		{"a package the gem does not have resolves from the app", gem + "/x.js", "pkg", []string{app}, "", cfg},
		{"a peer resolves from the app first, then from the gem's own copy", gem + "/lib/deep/x.js", "react/jsx-runtime", []string{app, gem}, "", cfg},
		{"a peer imported by a package the gem ships resolves from the app first", gem + "/node_modules/ms/lib/x.js", "react", []string{app, gem + "/node_modules/ms/lib"}, "", cfg},
		{"a file of a package the gem ships resolves beside itself, then from the app", gem + "/node_modules/ms/lib/x.js", "dep", []string{gem + "/node_modules/ms/lib", app}, "", cfg},
		{"a relative specifier is not a bare import", gem + "/lib/deep/x.js", "./nested", nil, "", cfg},
		{"a # subpath import belongs to the importer's package", gem + "/lib/deep/x.js", "#internal", nil, "", cfg},
		{"a name with a .. segment is not a package", gem + "/lib/deep/x.js", "@x/../ms", nil, "", cfg},
		{"a file that is not a gem's keeps its own lookup", app + "/app/views/x.js", "react", nil, "", cfg},
		{"a package the app installed in a gem's root keeps its own", app + "/node_modules/pkg/lib/x.js", "react", nil, "", appGem},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dirs, mappedGem := bareLookupDirs(tt.importer, tt.specifier, tt.cfg)
			if !slices.Equal(dirs, tt.dirs) || mappedGem != tt.mappedGem {
				t.Errorf("bareLookupDirs(%q, %q) = (%q, %q), want (%q, %q)",
					tt.importer, tt.specifier, dirs, mappedGem, tt.dirs, tt.mappedGem)
			}
		})
	}
}

// A gem's peers are re-read when its package.json changes, so a long-running server sees the edit.
func TestIsGemPeerRereadsAnEditedPackageJson(t *testing.T) {
	gem := filepath.ToSlash(t.TempDir())
	write := func(json string) {
		if err := os.WriteFile(filepath.FromSlash(gem+"/package.json"), []byte(json), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	write(`{"peerDependencies":{"react":"^18"}}`)
	if !isGemPeer(gem, "react") {
		t.Fatal("react is a peer")
	}

	write(`{"dependencies":{"react":"^18"}}`)
	if isGemPeer(gem, "react") {
		t.Error("react is no longer a peer once package.json drops it")
	}

	write(`not json`)
	if isGemPeer(gem, "react") {
		t.Error("a package.json that is not valid JSON lists no peers")
	}
}
