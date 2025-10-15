package utils

import (
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"joelmoss/proscenium/internal/debug"
	"joelmoss/proscenium/internal/types"
	"path"
	"regexp"
	"strings"

	esbuild "github.com/evanw/esbuild/pkg/api"
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

func HasExtension(name string) (extension string, found bool) {
	ext := path.Ext(name)
	return ext, ext != ""
}

func IsBareModule(name string) bool {
	return !path.IsAbs(name) && !PathIsRelative(name)
}

var IsBareSpecifier = IsBareModule

func IsUrl(name string) bool {
	var re = regexp.MustCompile(`^https?:\/\/`)
	return re.MatchString(name)
}

func PathIsRelative(name string) bool {
	var re = regexp.MustCompile(`^\.(\.)?\/`)
	return re.MatchString(name)
}

func ToDigest(s string) string {
	path := ""

	if types.Config.UseDevCSSModuleNames || types.Config.Environment == types.DevEnv {
		re := regexp.MustCompile(`[@/\.+]`)
		path = "__" + re.ReplaceAllLiteralString(strings.TrimPrefix(s, "/"), "-")

		debug.Debug(s, path)
	}

	hash := sha1.Sum([]byte(s))
	return hex.EncodeToString(hash[:])[0:8] + path
}

func pathIsJs(path string) bool {
	var re = regexp.MustCompile(`\.jsx?$`)
	return re.MatchString(path)
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
	return args.Kind == esbuild.ResolveJSImportStatement && PathIsCss(path) && pathIsJs(args.Importer)
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

func HasAlias(path string) (string, bool) {
	if len(types.Config.Aliases) > 0 {
		if aliasedPath, exists := types.Config.Aliases[path]; exists {
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

func PathIsRubyGem(path string) (gemName string, gemPath string, found bool) {
	for gemName, gemPath := range types.Config.RubyGems {
		if strings.HasPrefix(path, gemPath) {
			return gemName, gemPath, true
		}
	}
	return "", "", false
}

// Checks if the given path is a Ruby gem, ie. starts with "@rubygems/" or "node_modules/@rubygems".
// If the second argument is true, it will only return true if the path starts with
// "node_modules/@rubygems".
func IsRubyGem(path string, mustBeFromNodeModules ...bool) bool {
	// Default value is false if no argument provided
	_mustBeFromNodeModules := false
	if len(mustBeFromNodeModules) > 0 {
		_mustBeFromNodeModules = mustBeFromNodeModules[0]
	}

	if _mustBeFromNodeModules {
		return strings.HasPrefix(path, "node_modules/"+types.RubyGemsScope)
	}

	return strings.HasPrefix(path, types.RubyGemsScope) || strings.HasPrefix(path, "node_modules/"+types.RubyGemsScope)
}

func ResolveRubyGem(path string) (gemName string, gemPath string, err error) {
	name := extractScopedPackageName(path)

	if gemPath, exists := types.Config.RubyGems[name]; exists {
		return name, gemPath, nil
	} else {
		return "", "", fmt.Errorf("Could not resolve Ruby gem %q. Is %q in your Gemfile?", name, name)
	}
}

// Converts an absolute Rubygem file system path to a URL path.
//
// Example:
//
//	"/full/path/to/rubygems/@rubygems/foo/bar" -> "/node_modules/@rubygems/foo/bar"
func RubyGemPathToUrlPath(fsPath string) (urlPath string, found bool) {
	if gemName, gemPath, ok := PathIsRubyGem(fsPath); ok {
		suffix := strings.TrimPrefix(fsPath, gemPath)
		return path.Join("/node_modules", types.RubyGemsScope, gemName, suffix), true
	}

	return "", false
}

func ApplyQueryString(path string) string {
	if types.Config.QueryString == "" {
		return path
	}

	if strings.Contains(path, "?") {
		return path + "&" + types.Config.QueryString
	}
	return path + "?" + types.Config.QueryString
}
