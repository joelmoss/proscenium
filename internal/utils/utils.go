package utils

import (
	"fmt"
	"joelmoss/proscenium/internal/types"
	"path"
	"strings"

	esbuild "github.com/joelmoss/esbuild-internal/api"
)

func ToString(a interface{}) (string, bool) {
	aString, isString := a.(string)
	if isString {
		return aString, true
	}

	aBytes, isBytes := a.([]byte)
	if isBytes {
		return string(aBytes), true
	}

	return "", false
}

func KindToString(e esbuild.ResolveKind) string {
	kindStrings := []string{
		"ResolveNone",
		"ResolveEntryPoint",
		"ResolveJSImportStatement",
		"ResolveJSRequireCall",
		"ResolveJSDynamicImport",
		"ResolveJSRequireResolve",
		"ResolveCSSImportRule",
		"ResolveCSSComposesFrom",
		"ResolveCSSURLToken",
	}
	return kindStrings[e]
}

func HasExtension(name string) (extension string, found bool) {
	ext := path.Ext(name)
	return ext, ext != ""
}

func IsBareModule(name string) bool {
	return !strings.HasPrefix(name, "unbundle:") && !path.IsAbs(name) && !PathIsRelative(name)
}

var IsBareSpecifier = IsBareModule

func IsUrl(name string) bool {
	return strings.HasPrefix(name, "http://") || strings.HasPrefix(name, "https://")
}

func PathIsRelative(name string) bool {
	return strings.HasPrefix(name, "./") || strings.HasPrefix(name, "../")
}

func PathIsCss(path string) bool {
	return strings.HasSuffix(path, ".css")
}

func PathIsCssModule(path string) bool {
	return strings.HasSuffix(path, ".module.css")
}

func PathIsJsx(path string) bool {
	return strings.HasSuffix(path, ".jsx")
}

func PathIsTsx(path string) bool {
	return strings.HasSuffix(path, ".tsx")
}

func PathIsSvg(path string) bool {
	return strings.HasSuffix(path, ".svg")
}

func IsCssImportedFromJs(path string, args esbuild.OnResolveArgs) bool {
	return args.Kind == esbuild.ResolveJSImportStatement && PathIsCss(path)
}

func IsSvgImportedFromJsx(path string, args esbuild.OnResolveArgs) bool {
	return PathIsSvg(path) && IsImportedFromJsx(path, args)
}

func IsImportedFromJsx(path string, args esbuild.OnResolveArgs) bool {
	return args.Kind == esbuild.ResolveJSImportStatement && (PathIsJsx(args.Importer) || PathIsTsx(args.Importer))
}

func IsSvgImportedFromCss(path string, args esbuild.OnResolveArgs) bool {
	return PathIsSvg(path) && PathIsCss(args.Importer)
}

func RemoveRubygemPrefix(path string, gemName string) string {
	return strings.TrimPrefix(path, types.RubyGemsScope+gemName)
}

func HasAlias(path string, cfg *types.ConfigT) (string, bool) {
	if len(cfg.Aliases) > 0 {
		if aliasedPath, exists := cfg.Aliases[path]; exists {
			return aliasedPath, true
		}
	}

	return "", false
}

// Returns an empty string if the path is not a bare module.
func ExtractBareModule(path string) string {
	if !IsBareModule(path) {
		return ""
	}

	if strings.HasPrefix(path, "@") {
		// For scoped packages like @scope/package/file.js, return @scope/package
		firstSlash := strings.Index(path, "/")
		if firstSlash == -1 {
			return path
		}

		secondSlash := strings.Index(path[firstSlash+1:], "/")
		if secondSlash == -1 {
			return path
		}

		return path[:firstSlash+secondSlash+1]
	}

	// For non-scoped packages like package/file.js, return package
	firstSlash := strings.Index(path, "/")
	if firstSlash == -1 {
		return path
	}

	return path[:firstSlash]
}

// Extracts the package name from a path. For example, given the path "@rubygems/foo/bar.js", it
// will return "foo".
func extractScopedPackageName(path string) string {
	firstSlash := strings.Index(path, "/")
	if firstSlash == -1 {
		return ""
	}

	rest := path[firstSlash+1:]
	secondSlash := strings.Index(rest, "/")
	if secondSlash == -1 {
		// No second slash, return everything after first slash
		return rest
	}

	return rest[:secondSlash]
}

// A reference to one bundled Ruby gem, and everything the callers of the old four-call sequence
// had to re-derive for themselves: which gem, where its root is, and what part of the path sits
// below that root.
//
// `Suffix` is always relative to `Root` and never carries the `@rubygems/` scope or the gem name.
// It is either empty, or begins with "/".
type GemRef struct {
	Name   string
	Root   string
	Suffix string
}

// The URL path Proscenium serves this gem reference at. The one spelling of the
// `/node_modules/@rubygems/<name><suffix>` rule, which is otherwise rebuilt by hand in five
// places across this package, internal/plugin and internal/resolver.
func (g GemRef) UrlPath() string {
	return path.Join("/node_modules", types.RubyGemsScope, g.Name, g.Suffix)
}

// Parses a specifier - `@rubygems/<name>/<suffix>`, optionally prefixed with any of `unbundle:`, a
// leading "/", and `node_modules/`.
//
// The three return values are "not a gem specifier at all" (false, no error), "a gem specifier
// naming a gem that is not bundled" (true, error), and a parsed reference. The error message is
// user-facing and asserted by test/rubygems_test.go, so it is reproduced verbatim.
//
// Answering "is it?" and "which gem?" in one call is the point. `IsRubyGem` and `ResolveRubyGem`
// disagreed about the accepted language: the predicate accepted a `node_modules/`-prefixed
// specifier, which the parser then mis-read, reporting the SCOPE as the missing gem name -
// `could not resolve Ruby gem "@rubygems"`. Correctness rested on each caller remembering to trim
// the prefix first, and internal/resolver/resolve.go did not.
func GemFromSpecifier(spec string, cfg *types.ConfigT) (GemRef, bool, error) {
	spec = strings.TrimPrefix(spec, "unbundle:")
	spec = strings.TrimPrefix(spec, "/")
	spec = strings.TrimPrefix(spec, "node_modules/")

	if !strings.HasPrefix(spec, types.RubyGemsScope) {
		return GemRef{}, false, nil
	}

	name := strings.TrimPrefix(ExtractBareModule(spec), types.RubyGemsScope)
	if name == "" {
		return GemRef{}, false, nil
	}

	root, ok := cfg.RubyGems[name]
	if !ok {
		return GemRef{}, true, fmt.Errorf("could not resolve Ruby gem %q. Is %q in your Gemfile?",
			name, name)
	}

	suffix := strings.TrimPrefix(spec, types.RubyGemsScope+name)
	if suffix == "/" {
		suffix = ""
	}

	return GemRef{Name: name, Root: root, Suffix: suffix}, true, nil
}

// Parses an absolute file system path, answering which bundled gem contains it. The filesystem-
// space counterpart of GemFromSpecifier, and the replacement for PathIsRubyGem.
//
// Longest root wins, and a root matches only at a "/" boundary. PathIsRubyGem took the first match
// of a bare HasPrefix from a Go map range, and gem roots are stored without a trailing separator -
// so a path under a root that merely shares a string prefix with another (`/gems/foo-ext` against
// `/gems/foo`) or sits under a nested root could be credited to the wrong gem, and picked
// differently from one call to the next in a single process. lib/proscenium/resolver.rb:18 already
// requires the boundary, comparing against `"#{root}/"`; this is the Go side agreeing.
func GemFromFsPath(fsPath string, cfg *types.ConfigT) (GemRef, bool) {
	var ref GemRef
	found := false

	for name, root := range cfg.RubyGems {
		trimmed := strings.TrimSuffix(root, "/")
		if fsPath != trimmed && !strings.HasPrefix(fsPath, trimmed+"/") {
			continue
		}

		if found {
			best := strings.TrimSuffix(ref.Root, "/")

			if len(trimmed) < len(best) {
				continue
			}

			// Two matching roots of equal length are the same directory, since the "/" boundary
			// rules out one being a prefix of the other - so this is two gems sharing a source
			// tree. Break the tie on name, or the answer comes from Go's map iteration order and
			// varies between calls in one process, which is the defect this function replaced.
			if len(trimmed) == len(best) && name >= ref.Name {
				continue
			}
		}

		ref = GemRef{Name: name, Root: root, Suffix: strings.TrimPrefix(fsPath, trimmed)}
		found = true
	}

	return ref, found
}

// Deprecated: use GemFromFsPath, which returns the suffix this drops.
func PathIsRubyGem(path string, cfg *types.ConfigT) (gemName string, gemPath string, found bool) {
	ref, ok := GemFromFsPath(path, cfg)
	return ref.Name, ref.Root, ok
}

// Checks if the given path is a Ruby gem, ie. starts with "@rubygems/" or "node_modules/@rubygems".
func IsRubyGem(path string) bool {
	return strings.HasPrefix(path, types.RubyGemsScope) ||
		strings.HasPrefix(path, "node_modules/"+types.RubyGemsScope)
}

func ResolveRubyGem(path string, cfg *types.ConfigT) (gemName string, gemPath string, err error) {
	name := extractScopedPackageName(path)

	if gemPath, exists := cfg.RubyGems[name]; exists {
		return name, gemPath, nil
	} else {
		return "", "", fmt.Errorf("could not resolve Ruby gem %q. Is %q in your Gemfile?", name, name)
	}
}

// Converts an absolute Rubygem file system path to a URL path.
//
// Example:
//
//	"/full/path/to/rubygems/@rubygems/foo/bar" -> "/node_modules/@rubygems/foo/bar"
func RubyGemPathToUrlPath(fsPath string, cfg *types.ConfigT) (urlPath string, found bool) {
	if ref, ok := GemFromFsPath(fsPath, cfg); ok {
		return ref.UrlPath(), true
	}

	return "", false
}
