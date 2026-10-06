# Shipping NPM dependencies in a gem

Your gem ships frontend code that imports npm packages. Declare them in a package.json at the root
of the gem, opt in, and an app using Proscenium installs them for your gem with its own package
manager: run `bundle exec proscenium install`, and your gem's imports resolve. Your files are served
from where Bundler installed the gem; nothing is copied. The app's side is in
[RubyGem NPM dependencies](rubygem_npm_dependencies.md).

## Checklist

`proscenium gem check` checks every item below except the third, which it cannot see: an import
your gem does not declare fails when an app builds it, naming your gem and the package. Run it in
your gem's directory, or pass it the directory or a built `.gem`, before every release
(`psm gem check` is the same command, under its shorter name):

```
$ proscenium gem check
some_ui_gem 1.0.0 passes every check: Proscenium can install its NPM dependencies.
```

It needs no bundle and exits 0 when the gem passes. Each problem it finds is printed with its fix:

```
$ proscenium gem check
Error: some_ui_gem lists react and react-dom as dependencies, so it would get its own copy and the page would load two.

To fix: List react and react-dom under peerDependencies instead, so the gem uses the app's copy.
(PSM-E-REACT)

Error: some_ui_gem's gemspec doesn't list package.json in spec.files, so the built gem won't include it.

To fix: Add package.json, and every frontend file the gem serves, to spec.files.
(PSM-E-GEM-FILES)
```

1. **Opt in** in your gemspec:

   ```ruby
   spec.metadata['proscenium.dependencies'] = 'true'
   ```

   A gem that ships a package.json without opting in is left alone, as Rails' own actiontext is.
2. **Put package.json and every frontend file in `spec.files`.** A gem installed from Git keeps
   files that are not in `spec.files`, and a built gem does not, so a package.json missing from it
   works for some apps and not others. `gem check` looks in your gem's root and in each top-level
   directory you ship something from, so a demo app beside your code, which you ship nothing
   from, is not flagged.
3. **Declare every package your frontend code imports.** Your imports resolve from your gem's own
   dependencies first. One you leave out resolves only if the app happens to install it too, as
   pnpm and Node do; when nothing provides it, the build fails naming your gem and the package.
4. **Declare React, and anything else the app must share, as a peer**, not a dependency. Otherwise
   your gem gets its own copy of React, and hooks break.
5. **Use only specs every package manager reads the same way:** semver ranges, dist-tags, `npm:`
   aliases to a registry package at a range or tag, `github:` and `git+https:`/`git+ssh:` URLs, `https:` tarball URLs, or `@rubygems/<gem>`
   for a gem your gemspec depends on. Not `file:`, `link:`, `workspace:` or `catalog:`, and no
   credential in a URL (a `user:password@` or token before the host, or a token, key or secret
   query parameter): the app commits what you declare. Package managers approve install scripts
   by name: Bun from the app's `trustedDependencies` or its default list, pnpm from the app's
   build approvals. So an app refuses your gem if it reaches an approved name, such as `esbuild`,
   through Git, a URL or an alias to another package. Depend on the registry package by that name.
6. **Ship built assets.** Proscenium refuses a gem with `preinstall`, `install`, `postinstall` or
   `prepare` scripts, or a `binding.gyp`: it never runs your build. Your dependencies' own scripts
   run only if the app approves them.
7. **`version` is optional.** Your gem's version is the one in the app's Gemfile.lock; the context
   does not copy package.json's.
8. **Make every platform variant the same, for JavaScript.** A gem built for several platforms
   ships one package.json per variant, but an app's lockfile holds one set of dependencies. Every
   variant must declare the same dependencies, opt in the same way, and pass `gem check`, frontend
   root included. An app with another variant in its Bundler cache refuses to install otherwise.

The name must be a valid npm package name once prefixed with `@rubygems/`, so a gem name with
capital letters cannot take part. Nor can one ending in a dot, or a Windows device name (`con`,
`prn`, `aux`, `nul`, `com1` to `com9`, `lpt1` to `lpt9`, with or without an extension), since no
Windows app could hold its context.

### A package.json that is not at the gem's root

Point Proscenium at its directory with `proscenium.frontend_root`, relative to the gem's root and
inside it:

```ruby
spec.metadata['proscenium.frontend_root'] = 'frontend'
```

`gem check` and `install` refuse a root outside the gem (PSM-E-FRONTEND-ROOT).

## An example package.json

```json
{
  "name": "@rubygems/some_ui_gem",
  "dependencies": { "ms": "^2.1.3" },
  "peerDependencies": { "react": "^18.3.1" }
}
```

## What the app commits for your gem

`bundle exec proscenium install` writes a context for your gem, which the app commits. It keeps
only what installing needs: `dependencies`, `peerDependencies`, `peerDependenciesMeta`,
`optionalDependencies`, `engines`, `os`, `cpu` and `libc`. Changing any of these in a release makes
each app's context stale until it reinstalls. Everything else stays in your package.json:

```json
{
  "name": "@rubygems/some_ui_gem",
  "private": true,
  "description": "Generated by Proscenium from the some_ui_gem gem. Do not edit; run bundle exec proscenium install.",
  "dependencies": {
    "ms": "^2.1.3"
  },
  "peerDependencies": {
    "react": "^18.3.1"
  },
  "proscenium": {
    "projection": "dependency-context-v1",
    "projectionSha256": "<hex>"
  }
}
```

When you release a version whose dependencies changed, the app's context is stale until it runs
`bundle exec proscenium install`, and the engine says so, naming your gem.
