package debug

import (
	"fmt"
	"os"
	"path"
	"runtime"
	"strings"

	"github.com/k0kubun/pp"
)

// Debug prints args if cfgDebug is true, ie. the caller's config has Debug enabled.
func Debug(cfgDebug bool, args ...any) {
	if cfgDebug {
		cwd, _ := os.Getwd()
		_, fn, line, _ := runtime.Caller(1)

		print(strings.TrimPrefix(fn, path.Join(cwd, "..")+"/"), line, args...)
	}
}

// Forces debug to be enabled for the duration of the function call
func FDebug(args ...any) {
	cwd, _ := os.Getwd()
	_, fn, line, _ := runtime.Caller(1)

	print(strings.TrimPrefix(fn, path.Join(cwd, "..")+"/"), line, args...)
}

func print(filename string, line int, args ...any) {
	pp.Println()
	pp.Print(fmt.Sprintf("DEBUG at ./%s:%d", filename, line))
	pp.Println()
	pp.Println(args...)
}
