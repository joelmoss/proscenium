# frozen_string_literal: true

require_relative 'helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

# A gem-introduced Git dependency with install or prepare scripts must not run them without the
# app's approval, on pnpm or Bun (#154, C55): the native behaviour the trusted-source rule and the
# `github:` allow-list rely on, checked against the managers themselves, and by the nightly canary
# against each line's newest patch. The dependency comes from a local bare repository over
# `git+file://`, so this needs no network; its scripts write marker files.
#
# Runs only with STAGE_A=1, because it needs pnpm and Bun. The package-manager CI job sets it.
describe 'a gem-introduced Git dependency' do
  GIT_SCRIPTS_DIR = Dir.mktmpdir('cli_git_scripts')
  Minitest.after_run { FileUtils.rm_rf(GIT_SCRIPTS_DIR) }

  before { skip 'set STAGE_A=1 to run (needs pnpm and Bun)' unless ENV['STAGE_A'] }

  def markers = File.join(GIT_SCRIPTS_DIR, 'markers')

  def git(dir, *args)
    out, status = Open3.capture2e('git', '-c', 'user.name=Proscenium', '-c',
                                  'user.email=proscenium@example.com', *args, chdir: dir)
    raise "git #{args.join(' ')} failed:\n#{out}" unless status.success?

    out
  end

  # A bare repository holding a package whose `scripts` each write a marker, and the commit.
  def repository(name, scripts)
    src = File.join(GIT_SCRIPTS_DIR, "#{name}-src")
    FileUtils.mkdir_p([src, markers])
    write = ->(hook) { "require('fs').writeFileSync('#{markers}/#{name}-#{hook}', '')" }
    package = { 'name' => name, 'version' => '1.0.0', 'main' => 'index.js',
                'scripts' => scripts.to_h { [it, "node -e \"#{write.call(it)}\""] } }
    File.write(File.join(src, 'package.json'), JSON.generate(package))
    File.write(File.join(src, 'index.js'), "module.exports = 1\n")
    git(src, 'init', '-q')
    git(src, 'add', '-A')
    git(src, 'commit', '-q', '-m', name)
    bare = File.join(GIT_SCRIPTS_DIR, "#{name}.git")
    git(GIT_SCRIPTS_DIR, 'clone', '-q', '--bare', src, bare)
    # `file:///D:/...` on Windows: after `file://` comes a host, so a drive letter needs a slash.
    "git+file://#{'/' unless bare.start_with?('/')}#{bare}##{git(src, 'rev-parse', 'HEAD').strip}"
  end

  # Installs an app whose only dependency arrives through a context, and returns the output and
  # whether the install succeeded.
  # `approve` names the package in the manager's allowlist, as the positive control.
  def install(manager, name, spec, approve: false)
    app = File.join(GIT_SCRIPTS_DIR, "#{manager}-#{name}#{'-approved' if approve}")
    FileUtils.mkdir_p(File.join(app, '.proscenium/packages/g'))
    File.write(File.join(app, '.proscenium/packages/g/package.json'),
               JSON.generate('name' => '@rubygems/g', 'private' => true,
                             'dependencies' => { name => spec }))
    package = { 'name' => 'app', 'private' => true }
    if manager == 'pnpm'
      # The control approves the Git package by its full specifier in allowBuilds, which is how
      # pnpm 11 and 12 name one.
      allow = approve ? "allowBuilds:\n  \"#{name}@#{spec}\": true\n" : ''
      File.write(File.join(app, 'pnpm-workspace.yaml'),
                 "packages:\n  - .proscenium/packages/*\n#{allow}")
      # No side-effects cache, so one install's build cannot stand in for another's.
      File.write(File.join(app, '.npmrc'), "side-effects-cache=false\n")
    else
      package['workspaces'] = ['.proscenium/packages/*']
      package['trustedDependencies'] = approve ? [name] : []
      File.write(File.join(app, 'bunfig.toml'), "[install]\nlinker = \"isolated\"\n")
    end
    File.write(File.join(app, 'package.json'), JSON.generate(package))

    out, status = Open3.capture2e(manager, 'install', chdir: app)
    [out, status.success?]
  end

  # The markers a package's scripts wrote.
  def ran(name) = Dir.exist?(markers) ? Dir.children(markers).grep(/\A#{name}-/).sort : []

  it 'runs no prepare, install or postinstall script on pnpm, and fails the install on prepare' do
    with_prepare = repository('pnpm-prepare', %w[prepare install postinstall])
    without = repository('pnpm-install', %w[install postinstall])

    out, ok = install('pnpm', 'pnpm-prepare', with_prepare)

    refute ok, out
    assert_includes out, 'ERR_PNPM_GIT_DEP_PREPARE_NOT_ALLOWED'
    out, ok = install('pnpm', 'pnpm-install', without)

    # pnpm refuses the install for the ignored scripts; it must be that refusal, not a failure
    # for some other reason.
    assert ok || out.include?('ERR_PNPM_IGNORED_BUILDS'), "pnpm install failed:\n#{out}"
    assert_empty ran('pnpm-prepare')
    assert_empty ran('pnpm-install')

    # The control: once the app approves the package, its scripts do run. A package of its own,
    # because pnpm 12 does not build a Git package an earlier install left unbuilt, approved or
    # not.
    approved = repository('pnpm-approved', %w[install postinstall])
    install('pnpm', 'pnpm-approved', approved, approve: true)

    assert_equal %w[pnpm-approved-install pnpm-approved-postinstall], ran('pnpm-approved')
  end

  it 'runs no prepare, install or postinstall script on Bun' do
    spec = repository('bun-scripts', %w[prepare install postinstall])

    out, ok = install('bun', 'bun-scripts', spec)

    assert ok, "bun install failed:\n#{out}"
    assert_empty ran('bun-scripts')

    # The control: once the app trusts the package, its install scripts do run.
    install('bun', 'bun-scripts', spec, approve: true)

    refute_empty ran('bun-scripts')
  end
end
