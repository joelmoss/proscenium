// Command probe builds a list of entry points through Proscenium's engine and records, for each,
// where every module and import came from. It is the Stage A driver for #154: run against a
// baseline install and against one with dependency contexts, and compare the two outputs.
//
// It needs no Rails app. The caller supplies what Rails would: the root, the bundled gem map, and
// the app's aliases and externals.
//
//	go run ./test/package_manager/stage_a/probe -root APP -gems gems.tsv -entries entries.txt \
//	  -out DIR [-context hue=APP/.proscenium/packages/hue] [-alias k=v] [-external x] [-unbundle]
//
// gems.tsv has one `name<TAB>root` line per bundled gem. entries.txt has one entry per line, in
// the form BuildToString takes (`node_modules/@rubygems/hue/lib/hue/toast.js`). For each entry it
// writes the build output to DIR and a line to DIR/summary.tsv: the entry, ok or failed, and for
// a bundled build the sorted module paths esbuild names in its `// path` comments, or for an
// unbundled one the sorted import URLs. Paths under the root are made root-relative, so two
// runs in different directories compare as text.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/types"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

type pairs map[string]string

func (p pairs) String() string { return fmt.Sprint(map[string]string(p)) }

func (p pairs) Set(s string) error {
	k, v, ok := strings.Cut(s, "=")
	if !ok {
		return fmt.Errorf("want key=value, got %q", s)
	}
	p[k] = v

	return nil
}

type list []string

func (l *list) String() string     { return strings.Join(*l, ",") }
func (l *list) Set(s string) error { *l = append(*l, s); return nil }

var (
	moduleComment = regexp.MustCompile(`(?m)^// (\S+)$`)
	importURL     = regexp.MustCompile(`(?:from|import)\s*\(?\s*"([^"]+)"`)
)

func main() {
	root := flag.String("root", "", "app root")
	gems := flag.String("gems", "", "name<TAB>root file")
	entries := flag.String("entries", "", "file of entry points")
	out := flag.String("out", "", "output directory")
	unbundle := flag.Bool("unbundle", false, "build unbundled")
	contexts, aliases := pairs{}, pairs{}
	var externals list
	flag.Var(contexts, "context", "gem=context dir (repeatable); turns the Stage A seam on")
	flag.Var(aliases, "alias", "key=value (repeatable)")
	flag.Var(&externals, "external", "external specifier (repeatable)")
	flag.Parse()

	// The seam compares resolved real paths against the root as text.
	realRoot, err := filepath.EvalSymlinks(*root)
	check(err)
	realRoot = filepath.ToSlash(realRoot)

	write := false
	cfg := &types.ConfigT{
		RootPath:    realRoot,
		OutputDir:   "public/assets",
		Environment: types.DevEnv,
		Bundle:      !*unbundle,
		RubyGems:    readGems(*gems),
		Aliases:     aliases,
		External:    externals,
		Write:       &write,
	}
	if len(contexts) > 0 {
		cfg.DependencyContexts = contexts
	}

	check(os.MkdirAll(*out, 0o755))
	summary, err := os.Create(filepath.Join(*out, "summary.tsv"))
	check(err)
	defer summary.Close()

	for _, entry := range readLines(*entries) {
		ok, code, _ := builder.BuildToString(entry, cfg)
		check(os.WriteFile(filepath.Join(*out, strings.ReplaceAll(entry, "/", "__")), []byte(code), 0o644))

		status := "ok"
		if !ok {
			status = "failed"
		}

		var found []string
		pattern := moduleComment
		if *unbundle {
			pattern = importURL
		}
		for _, m := range pattern.FindAllStringSubmatch(code, -1) {
			found = append(found, strings.TrimPrefix(m[1], realRoot))
		}
		slices.Sort(found)
		found = slices.Compact(found)

		fmt.Fprintf(summary, "%s\t%s\t%s\n", entry, status, strings.Join(found, " "))
		fmt.Printf("%-7s %s (%d)\n", status, entry, len(found))
	}
}

func readGems(path string) map[string]string {
	gems := map[string]string{}
	for _, line := range readLines(path) {
		name, root, ok := strings.Cut(line, "\t")
		if !ok {
			check(fmt.Errorf("%s: want name<TAB>root, got %q", path, line))
		}
		gems[name] = root
	}

	return gems
}

func readLines(path string) []string {
	f, err := os.Open(path)
	check(err)
	defer f.Close()

	var lines []string
	s := bufio.NewScanner(f)
	for s.Scan() {
		if line := strings.TrimSpace(s.Text()); line != "" {
			lines = append(lines, line)
		}
	}
	check(s.Err())

	return lines
}

func check(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
