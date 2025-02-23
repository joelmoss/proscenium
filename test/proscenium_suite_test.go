package proscenium_test

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/types"
	"os"
	"path"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var cwd, _ = os.Getwd()
var fixturesRoot string = filepath.Join(cwd, "..", "fixtures")

func TestProscenium(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Proscenium Test Suite")
}

var _ = BeforeSuite(func() {
	_, filename, _, _ := runtime.Caller(0)
	assetPath := path.Join(path.Dir(filename), "..", "fixtures", "dummy", "public", "assets")
	dir, _ := os.ReadDir(assetPath)
	for _, d := range dir {
		os.RemoveAll(path.Join(assetPath, d.Name()))
	}
})

var _ = BeforeEach(func() {
	importmap.Reset()
	types.Config.Reset()
	types.Config.Environment = types.TestEnv

	_, filename, _, _ := runtime.Caller(0)
	root := path.Dir(filename)
	types.Config.RootPath = path.Join(root, "..", "fixtures", "dummy")
	types.Config.GemPath = path.Join(root, "..")

	// Currently only used by the SVG plugin
	plugin.DiskvCache.EraseAll()
})

var _ = AfterEach(func() {
	gock.Off()
})
