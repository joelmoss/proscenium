package golib_test

import (
	"joelmoss/proscenium/golib"
	"os"
	"path"
	"testing"

	"github.com/gkampitakis/go-snaps/snaps"
	"github.com/k0kubun/pp/v3"
	"github.com/stretchr/testify/assert"
)

func root() string {
	cwd, _ := os.Getwd()
	return path.Join(cwd, "../", "test", "internal")
}

func TestBasic(t *testing.T) {
	result := golib.Build("lib/foo.js", root(), 2, false)

	snaps.MatchSnapshot(t, string(result.OutputFiles[0].Contents))
}

func TestUnknownPath(t *testing.T) {
	result := golib.Build("unknown.js", root(), 2, false)

	assert.Equal(t, result.Errors[0].Text, "Could not resolve \"unknown.js\"")
}

func TestSvg(t *testing.T) {
	result := golib.Build("lib/svg/component.jsx", root(), 2, false)

	pp.Println(result)
	snaps.MatchSnapshot(t, string(result.OutputFiles[0].Contents))
}

func TestNodeEnv(t *testing.T) {
	result := golib.Build("lib/define_node_env.js", root(), 2, false)

	snaps.MatchSnapshot(t, string(result.OutputFiles[0].Contents))
}
