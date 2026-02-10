package proscenium_test

import (
	"fmt"
	b "joelmoss/proscenium/internal/builder"
	"joelmoss/proscenium/internal/debug"
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

type debugType bool
type bundleType bool
type unbundleType bool
type asProduction bool

const Debug = debugType(true)
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

var _ = BeforeEach(func() {
	fileToAssertCode = ""

	types.Config.Reset()
	types.Config.InternalTesting = true
	types.Config.Environment = types.TestEnv

	_, filename, _, _ := runtime.Caller(0)
	root := path.Dir(filename)
	types.Config.RootPath = path.Join(root, "..", "fixtures", "dummy")
	types.Config.OutputDir = "public/assets"
	types.Config.GemPath = path.Join(root, "..")

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

var AssertCode = func(expectedCode string, args ...any) {
	GinkgoHelper()

	description := ""
	assertArgs := []any{}
	specArgs := []any{}

	// If second argument is a string, then a test description has been provided as the first
	// argument. That means expectedCode is the second argument.
	if len(args) > 0 && reflect.TypeOf(args[0]).Kind() == reflect.String {
		description = expectedCode
		expectedCode = args[0].(string)
		args = args[1:]
	}

	for _, arg := range args {
		switch t := reflect.TypeOf(arg); {
		case t == reflect.TypeOf(Debug):
		case t == reflect.TypeOf(Bundle):
		case t == reflect.TypeOf(Unbundle):
		case t == reflect.TypeOf(Production):
			assertArgs = append(assertArgs, arg)
		default:
			specArgs = append(specArgs, arg)
		}
	}

	It("resolves", specArgs, func() {
		if fileToAssertCode == "" {
			panic("You must assign a file path to `assertCodeForFile` before calling `AssertCode()`")
		}

		for _, arg := range args {
			switch t := reflect.TypeOf(arg); {
			case t == reflect.TypeOf(Debug):
				debug.Enable()
			case t == reflect.TypeOf(Bundle):
				types.Config.Bundle = true
			case t == reflect.TypeOf(Unbundle):
				types.Config.Bundle = false
			case t == reflect.TypeOf(Production):
				types.Config.InternalTesting = false
				types.Config.Environment = types.ProdEnv
			}
		}

		if description != "" {
			By(description)
		}

		_, result, _ := b.BuildToString(fileToAssertCode)
		Expect(result).To(ContainCode(expectedCode))
	})
}

var AssertCodeFromFunc = func(expectedCode func() string, args ...any) {
	GinkgoHelper()

	description := ""
	assertArgs := []any{}
	specArgs := []any{}

	for _, arg := range args {
		switch t := reflect.TypeOf(arg); {
		case t == reflect.TypeOf(Debug):
		case t == reflect.TypeOf(Bundle):
		case t == reflect.TypeOf(Unbundle):
		case t == reflect.TypeOf(Production):
			assertArgs = append(assertArgs, arg)
		default:
			specArgs = append(specArgs, arg)
		}
	}

	It("resolves", specArgs, func() {
		if fileToAssertCode == "" {
			panic("You must assign a file path to `assertCodeForFile` before calling `AssertCode()`")
		}

		for _, arg := range args {
			switch t := reflect.TypeOf(arg); {
			case t == reflect.TypeOf(Debug):
				debug.Enable()
			case t == reflect.TypeOf(Bundle):
				types.Config.Bundle = true
			case t == reflect.TypeOf(Unbundle):
				types.Config.Bundle = false
			case t == reflect.TypeOf(Production):
				types.Config.InternalTesting = false
				types.Config.Environment = types.ProdEnv
			}
		}

		if description != "" {
			By(description)
		}

		_, result, _ := b.BuildToString(fileToAssertCode)
		Expect(result).To(ContainCode(expectedCode()))
	})
}
