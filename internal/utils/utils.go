package utils

import (
	"fmt"
	"joelmoss/proscenium/internal/types"
	"path"
	"path/filepath"
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
	return !strings.HasPrefix(name, "unbundle:") && !UrlPathIsAbs(name) && !FsPathIsAbs(name) &&
		!PathIsRelative(name)
}

var IsBareSpecifier = IsBareModule

//                    TWO PATH SPACES, ONE STRING TYPE
//
//  URL space                                Filesystem space
//  always "/"                               OS-form: "/" or "\\", maybe "C:"
//  what the browser asks for                what esbuild and os.* hand back
//
//  /app/views/x.css                         /Users/j/app/app/views/x.css
//  /node_modules/@rubygems/foo/a.js         C:\\Users\\j\\app\\app\\views\\x.css
//          ^                                            |
//          |  UrlPathFromFsPath                         |  filepath.ToSlash at ingress
//          |  GemRef.UrlPath()                          v
//          +-------------------------------------  C:/Users/j/app/...
//
// Every path held in a Go variable below the esbuild boundary is slash-form. Go's os package and
// the Win32 API both accept "/", and Ruby cooperates: Rails.root.to_s and
// Gem::Specification#full_gem_path are slash-form on Windows too. Paths arriving from esbuild are
// converted once, at the door, and paths built for esbuild go through JoinFsPath.
//
// ABSOLUTENESS IS SPACE-DEPENDENT, so there are two predicates and never one. Using a
// drive-letter-aware check where the question is "is this rooted at the app?" produces
// C:/app/C:/app/x.js; using the URL check where the question is "is this a real file?" sends a
// resolved Windows path back round the resolver as though it were relative. The site's own
// comment says which question it is asking.

// UrlPathIsAbs reports whether p is rooted in URL space: the browser asked for it from the app
// root. "C:/app/x.js" is not - it is a filesystem path that happens to be absolute.
func UrlPathIsAbs(p string) bool {
	return strings.HasPrefix(p, "/")
}

// FsPathIsAbs reports whether p names a file from the filesystem root: a leading "/", or a
// Windows drive or UNC root when running on Windows. filepath.IsAbs alone is not enough, because
// it answers false for "/app/x.js" on Windows, and that is the form every path takes here.
func FsPathIsAbs(p string) bool {
	return strings.HasPrefix(p, "/") || filepath.IsAbs(p)
}

// JoinFsPath joins filesystem path segments and returns the result in slash-form.
//
// filepath.Join rather than path.Join because only filepath understands what it is joining on
// Windows: path.Join collapses "//server/share" to "/server/share", destroying a UNC root, and
// does not know where a drive root ends when it cleans away "..". ToSlash then puts the result
// back into the one form everything below the boundary uses.
func JoinFsPath(elem ...string) string {
	return filepath.ToSlash(filepath.Join(elem...))
}

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
// `/node_modules/@rubygems/<name><suffix>` rule, which used to be rebuilt by hand in five places.
// One hand-built copy is left, at internal/plugin/bundless.go:190; it goes with the F-GOUTILS-1
// step-2 pass.
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

	// Cleaned as a relative path so that a leading ".." survives to be caught: path.Clean on a
	// rooted path rewrites "/../x" to "/x", which would fold an escape back into the gem. The URL
	// half of an answer cleans the suffix (UrlPath is path.Join) while the file half joins it onto
	// the root as given, so "@rubygems/foo/../bar/x.js" named gem "bar" in the browser and a
	// directory beside foo's root on disk.
	rest := strings.TrimPrefix(spec, types.RubyGemsScope+name)
	cleaned := path.Clean("." + rest)
	if cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return GemRef{}, true, fmt.Errorf("%q escapes the root of gem %q", spec, name)
	}

	suffix := ""
	if cleaned != "." {
		suffix = "/" + cleaned

		// A trailing slash asks for a directory, and esbuild honours the difference: given both
		// `lib.js` and `lib/index.js`, `./lib/` is the second and `./lib` the first. Clean drops
		// it, so it is put back.
		if strings.HasSuffix(rest, "/") {
			suffix += "/"
		}
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
// differently from one call to the next in a single process. Proscenium::Resolver.resolve already
// requires the boundary, comparing against `"#{root}/"`; this is the Go side agreeing, except that
// it also accepts a path equal to the root itself.
func GemFromFsPath(fsPath string, cfg *types.ConfigT) (GemRef, bool) {
	var ref GemRef
	found := false

	for name, root := range cfg.RubyGems {
		trimmed := strings.TrimSuffix(root, "/")

		// The "/" boundary is an index check, not `HasPrefix(fsPath, trimmed+"/")`: that built a
		// string per gem per call, and this runs for every module a build loads, against every gem
		// in the Gemfile. HasPrefix has to stay first: it guarantees `len(fsPath) >= len(trimmed)`,
		// which is what makes the index safe.
		if !strings.HasPrefix(fsPath, trimmed) ||
			(len(fsPath) != len(trimmed) && fsPath[len(trimmed)] != '/') {
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

// The URL Proscenium serves the file at `fsPath` from: a bundled gem's file under its
// `/node_modules/@rubygems/<name>` prefix, a file under the app root at its root-relative path, and
// nothing for a file under neither. Gem roots are tried first, because a vendored gem sits under the
// app root. The app root matches at a "/" boundary only, the rule GemFromFsPath applies to gem
// roots: `/app-other/x.css` is not under `/app`.
//
// This rule used to be spelled by hand in five places, two of which fell through with the raw
// filesystem path when neither root matched, and one of which (`rootPathToUrlPath`) had no
// boundary. This is now the only one.
func UrlPathFromFsPath(fsPath string, cfg *types.ConfigT) (urlPath string, ok bool) {
	// Both sides are compared as text, so a `..` left in either would walk out of a root that
	// still looks like a prefix: `/app/../outside.css` answered "/../outside.css", inside "/app".
	// Today's callers pass a path esbuild or path.Join has already cleaned; this does not rely on
	// that.
	fsPath = cleanFsPath(fsPath)

	if ref, found := GemFromFsPath(fsPath, cfg); found {
		return ref.UrlPath(), true
	}

	// An unset root would be a prefix of everything, and this function exists to say "no". Checked
	// before the trim: a root of "/" trims to "" too, and that one is real.
	if cfg.RootPath == "" {
		return "", false
	}

	root := strings.TrimSuffix(cleanFsPath(cfg.RootPath), "/")
	if fsPath == root {
		return "/", true
	}

	if strings.HasPrefix(fsPath, root) && len(fsPath) > len(root) && fsPath[len(root)] == '/' {
		return fsPath[len(root):], true
	}

	return "", false
}

// Cleaned by the platform's own rules, in slash-form. On Windows a leading "//" is a UNC root - the
// form a gem installed on a network share has - and path.Clean collapsed it to "/", after which
// nothing compared against the gem roots, which are used as given, could match. Everywhere else
// filepath.Clean is path.Clean, so Unix paths keep their meaning.
func cleanFsPath(p string) string {
	return filepath.ToSlash(filepath.Clean(p))
}
