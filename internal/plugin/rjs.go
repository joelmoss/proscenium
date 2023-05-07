package plugin

import (
	esbuild "github.com/evanw/esbuild/pkg/api"
)

func Rjs(baseUrl string) esbuild.Plugin {
	return esbuild.Plugin{
		Name: "rjs",
		Setup: func(build esbuild.PluginBuild) {
			// Server rendered JS are served directly from Rails.
			build.OnResolve(esbuild.OnResolveOptions{Filter: `\.rjs$`},
				func(args esbuild.OnResolveArgs) (esbuild.OnResolveResult, error) {
					return esbuild.OnResolveResult{
						Path:     args.Path,
						External: true,
					}, nil
				})

			// FIXME: This is not working. Puma (and also Falcon) is crashing with:
			// 	objc[60057]: +[NSNumber initialize] may have been in progress in another thread when
			// 	fork() was called. We cannot safely call it or ignore it in the fork() child process.
			// 	Crashing instead. Set a breakpoint on objc_initializeAfterForkError to debug.
			//
			// Disabling for now, which means RJS filess will not be bundled.
			//
			// build.OnLoad(esbuild.OnLoadOptions{Filter: `\.rjs$`},
			// 	func(args esbuild.OnLoadArgs) (esbuild.OnLoadResult, error) {
			// 		url, err := url.JoinPath(baseUrl, args.Path)
			// 		if err != nil {
			// 			return esbuild.OnLoadResult{}, err
			// 		}

			// 		// contents, err := DownloadURL(url, false)

			// 		contents := make(chan string)
			// 		go func() {
			// 			c, _ := DownloadURL(url, false)
			// 			contents <- c
			// 		}()
			// 		result := <-contents

			// 		// if err != nil {
			// 		// 	return esbuild.OnLoadResult{}, err
			// 		// }

			// 		return esbuild.OnLoadResult{
			// 			Contents:   &result,
			// 			ResolveDir: filepath.Dir(args.Path),
			// 			Loader:     esbuild.LoaderJS,
			// 		}, nil
			// 	})
		},
	}
}
