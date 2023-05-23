package proscenium_test

import (
	"joelmoss/proscenium/internal/importmap"
	"joelmoss/proscenium/internal/plugin"
	"joelmoss/proscenium/internal/types"
	"testing"

	"github.com/h2non/gock"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

func TestProscenium(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Proscenium Test Suite")
}

var _ = BeforeEach(func() {
	types.Env = types.TestEnv
	importmap.Contents = &types.ImportMap{}
	plugin.DiskvCache.EraseAll()
})

var _ = AfterEach(func() {
	gock.Off()
})
