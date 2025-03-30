package debug

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/k0kubun/pp"
)

var Enabled = false

func Enable() {
	Enabled = true
}

func Debug(args ...any) {
	if Enabled {
		cwd, _ := os.Getwd()
		_, fn, line, _ := runtime.Caller(1)

		print(strings.TrimPrefix(fn, filepath.Join(cwd, "..")+"/"), line, args...)
	}
}

// Forces debug to be enabled for the duration of the function call
func FDebug(args ...any) {
	Enabled = true

	cwd, _ := os.Getwd()
	_, fn, line, _ := runtime.Caller(1)

	print(strings.TrimPrefix(fn, filepath.Join(cwd, "..")+"/"), line, args...)

	Enabled = false
}

func print(filename string, line int, args ...any) {
	pp.Println()
	pp.Print(fmt.Sprintf("DEBUG at ./%s:%d", filename, line))
	pp.Println()
	pp.Println(args...)
}
