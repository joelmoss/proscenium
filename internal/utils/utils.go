package utils

import (
	"crypto/sha1"
	"encoding/hex"
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

func IsBareModule(name string) bool {
	return !path.IsAbs(name) && !PathIsRelative(name)
}

func IsUrl(name string) bool {
	var re = regexp.MustCompile(`^https?:\/\/`)
	return re.MatchString(name)
}

func IsEncodedUrl(name string) bool {
	var re = regexp.MustCompile(`^https?%3A%2F%2F`)
	return re.MatchString(name)
}

func PathIsRelative(name string) bool {
	var re = regexp.MustCompile(`^\.(\.)?\/`)
	return re.MatchString(name)
}

func ToDigest(s string) string {
	hash := sha1.Sum([]byte(s))
	return hex.EncodeToString(hash[:])[0:8]
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

func PathIsSvg(path string) bool {
	return strings.HasSuffix(path, ".svg")
}

func IsCssModuleImportedFromCssModule(path string, args esbuild.OnResolveArgs) bool {
	return args.Kind == esbuild.ResolveCSSImportRule && PathIsCssModule(path) && PathIsCssModule(args.Importer)
}

func IsCssImportedFromJs(path string, args esbuild.OnResolveArgs) bool {
	return args.Kind == esbuild.ResolveJSImportStatement && PathIsCss(path) && pathIsJs(args.Importer)
}

func IsSvgImportedFromJsx(path string, args esbuild.OnResolveArgs) bool {
	return args.Kind == esbuild.ResolveJSImportStatement && PathIsSvg(path) && PathIsJsx(args.Importer)
}

func IsSvgImportedFromCss(path string, args esbuild.OnResolveArgs) bool {
	return PathIsSvg(path) && PathIsCss(args.Importer)
}
