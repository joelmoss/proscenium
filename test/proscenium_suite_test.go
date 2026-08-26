package proscenium_test

import (
	"fmt"
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/types"
	. "joelmoss/proscenium/test/support"
	"os"
	"path"
	"reflect"
	"runtime"
	"testing"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

type bundleType bool
type unbundleType bool
type asProduction bool

const Bundle = bundleType(true)
const Unbundle = unbundleType(true)
const Production = asProduction(true)

var cwd, _ = os.Getwd()
var fixturesRoot string = path.Join(cwd, "..", "fixtures")

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

// Builds the default config every spec starts from. Specs that need something different
// (aliases, precompile paths, ruby gems, bundle mode) mutate the `testConfig` package var
// directly in their own BeforeEach, rather than the old shared types.Config global.
func newTestConfig() *types.ConfigT {
	_, filename, _, _ := runtime.Caller(0)
	root := path.Dir(filename)

	return &types.ConfigT{
		CodeSplitting:   true,
		Bundle:          true,
		InternalTesting: true,
		Environment:     types.TestEnv,
		RootPath:        path.Join(root, "..", "fixtures", "dummy"),
		OutputDir:       "public/assets",
		GemPath:         path.Join(root, ".."),
	}
}

// The config for the spec currently running. Rebuilt fresh in BeforeEach for every spec -
// never shared or mutated concurrently, since Ginkgo runs specs sequentially in this suite.
var testConfig *types.ConfigT

var _ = BeforeEach(func() {
	fileToAssertCode = ""
	testConfig = newTestConfig()

	// Currently only used by the SVG plugin
	plugin.DiskvCache.EraseAll()
})

var _ = AfterEach(func() {
	gock.Off()
})

var fileToAssertCode = ""

var EntryPoint = func(entryPoint string, container func()) {
	Describe(fmt.Sprintf("(entrypoint: %s)", entryPoint), func() {
		BeforeEach(func() {
			fileToAssertCode = entryPoint
		})

		AfterEach(func() {
			fileToAssertCode = ""
		})

		container()
	})
}

// Builds a copy of testConfig with the given markers (Bundle/Unbundle/Production) applied. Never
// mutates testConfig itself - each spec gets its own independent *ConfigT.
func configWithMarkers(args []any) *types.ConfigT {
	cfg := *testConfig

	for _, arg := range args {
		switch t := reflect.TypeOf(arg); {
		case t == reflect.TypeOf(Bundle):
			cfg.Bundle = true
		case t == reflect.TypeOf(Unbundle):
			cfg.Bundle = false
		case t == reflect.TypeOf(Production):
			cfg.InternalTesting = false
			cfg.Environment = types.ProdEnv
		}
	}

	return &cfg
}

func isMarker(arg any) bool {
	t := reflect.TypeOf(arg)
	return t == reflect.TypeOf(Bundle) || t == reflect.TypeOf(Unbundle) || t == reflect.TypeOf(Production)
}

var AssertCode = func(expectedCode string, args ...any) {
	GinkgoHelper()

	description := ""
	specArgs := []any{}

	// If second argument is a string, then a test description has been provided as the first
	// argument. That means expectedCode is the second argument.
	if len(args) > 0 && reflect.TypeOf(args[0]).Kind() == reflect.String {
		description = expectedCode
		expectedCode = args[0].(string)
		args = args[1:]
	}

	for _, arg := range args {
		if !isMarker(arg) {
			specArgs = append(specArgs, arg)
		}
	}

	It("resolves", specArgs, func() {
		if fileToAssertCode == "" {
			panic("You must assign a file path to `assertCodeForFile` before calling `AssertCode()`")
		}

		cfg := configWithMarkers(args)

		if description != "" {
			By(description)
		}

		_, result, _ := b.BuildToString(fileToAssertCode, cfg)
		Expect(result).To(ContainCode(expectedCode))
	})
}

var AssertCodeFromFunc = func(expectedCode func() string, args ...any) {
	GinkgoHelper()

	specArgs := []any{}

	for _, arg := range args {
		if !isMarker(arg) {
			specArgs = append(specArgs, arg)
		}
	}

	It("resolves", specArgs, func() {
		if fileToAssertCode == "" {
			panic("You must assign a file path to `assertCodeForFile` before calling `AssertCode()`")
		}

		cfg := configWithMarkers(args)

		_, result, _ := b.BuildToString(fileToAssertCode, cfg)
		Expect(result).To(ContainCode(expectedCode()))
	})
}
