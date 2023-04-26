package utils

import (
	"crypto/sha1"
	"encoding/hex"
	"regexp"
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
