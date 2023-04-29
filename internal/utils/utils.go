package utils

import (
	"crypto/sha1"
	"encoding/hex"
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
	var re = regexp.MustCompile(`(?m)^(@[a-z0-9-~][a-z0-9-._~]*\/)?[a-z0-9-~][a-z0-9-._~]*$`)
	return re.MatchString(name)
}

func IsUrl(name string) bool {
	var re = regexp.MustCompile(`^https?:\/\/`)
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

func IsCssImportedFromJs(path string, args esbuild.OnResolveArgs) bool {
	return args.Kind == esbuild.ResolveJSImportStatement &&
		PathIsCss(path) &&
		pathIsJs(args.Importer)
}

func IsSvgImportedFromJsx(path string, args esbuild.OnResolveArgs) bool {
	return args.Kind == esbuild.ResolveJSImportStatement &&
		strings.HasSuffix(path, ".svg") &&
		strings.HasSuffix(args.Importer, ".jsx")
}
