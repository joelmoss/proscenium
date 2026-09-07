module joelmoss/proscenium

go 1.25.7

// To update esbuild-internal, take the newest tag from
// https://github.com/joelmoss/esbuild-internal/tags - `v<upstream esbuild version>` for a plain
// sync, `v<upstream version>-<short sha>` when the fork carries commits on top - then run
// `GOWORK=off go get github.com/joelmoss/esbuild-internal@<tag>` and `GOWORK=off go mod tidy`.
//
// GOWORK=off is not optional: go.work points at a local checkout of the fork, and with the
// workspace on, both commands resolve that directory instead of the tag and leave go.sum alone.

require (
	github.com/joelmoss/esbuild-internal v0.28.2-2c2bc77d
	github.com/k0kubun/pp v3.0.1+incompatible
	github.com/onsi/ginkgo/v2 v2.32.1
	github.com/peterbourgon/diskv v2.0.1+incompatible
	github.com/sergi/go-diff v1.4.0
)

require (
	github.com/Masterminds/semver/v3 v3.5.0 // indirect
	github.com/go-logr/logr v1.4.4 // indirect
	github.com/go-task/slim-sprig/v3 v3.0.0 // indirect
	github.com/google/btree v1.1.3 // indirect
	github.com/google/go-cmp v0.7.0 // indirect
	github.com/google/pprof v0.0.0-20260906184651-6331bc6350fe // indirect
	github.com/h2non/parth v0.0.0-20190131123155-b4df798d6542 // indirect
	github.com/k0kubun/colorstring v0.0.0-20150214042306-9440f1994b88 // indirect
	github.com/mattn/go-colorable v0.1.15 // indirect
	github.com/mattn/go-isatty v0.0.24 // indirect
	github.com/stretchr/testify v1.11.1 // indirect
	go.yaml.in/yaml/v3 v3.0.4 // indirect
	golang.org/x/mod v0.40.0 // indirect
	golang.org/x/net v0.58.0 // indirect
	golang.org/x/sync v0.22.0 // indirect
	golang.org/x/tools v0.49.0 // indirect
)

require (
	4d63.com/collapsewhitespace v0.0.0-20190109064012-23971e8e1f30
	github.com/MakeNowJust/heredoc v1.0.0
	github.com/gregjones/httpcache v0.0.0-20190611155906-901d90724c79
	github.com/h2non/gock v1.2.0
	github.com/onsi/gomega v1.43.0
	github.com/peterbourgon/mergemap v0.0.1
	github.com/riking/cssparse v0.0.0-20180325025645-c37ded0aac89
	github.com/rogpeppe/go-internal v1.14.1 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.41.0 // indirect
	gopkg.in/yaml.v3 v3.0.1
)
