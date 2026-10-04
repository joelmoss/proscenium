# frozen_string_literal: true

require_relative 'helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../package_manager/stage_a/bundle'

# The fixture bundle, installed once for every class in this file: nested `describe`s are classes
# of their own, so a class-level memo would install it again for each.
#
# C27: the app's directory name has a space and a non-ASCII character and is 120 characters
# longer than it needs to be, so every install here runs from such a path, on every host. On
# Windows that takes the managers' deepest paths past the old 260-character limit. (Not the
# mktmpdir prefix: Dir::Tmpname strips everything but [-.,0-9A-Za-z_~] from it.) The bundle path
# beside it stays short, since Bundler's own Git cache is not Proscenium's to qualify.
module InstallFixture
  DIR = Dir.mktmpdir('cli_install')
  APP = "app ü #{'long-path-' * 12}".freeze
  Minitest.after_run do
    StageA::Bundle.writable!(DIR)
    FileUtils.rm_rf(DIR)
  end

  def self.roots = @roots ||= StageA::Bundle.install(DIR, app: APP)
end

# `proscenium install` and `install --frozen`, end to end: the Stage A fixture gems, genuinely
# installed by Bundler, an app on pnpm or Bun, and the real manager (#154, Gate B rows).
#
# Runs only with STAGE_A=1: it needs pnpm, Bun and the network. The stage-a CI job sets it.
describe 'proscenium install' do
  LIB = File.expand_path('../../lib', __dir__)
  EXE = File.expand_path('../../exe/proscenium', __dir__)
  GEMS = %w[gem_npm stage_a_hue_shape stage_a_widget_a stage_a_widget_b].freeze
  WIDGETS = %w[stage_a_widget_a stage_a_widget_b].freeze
  BUNDLE = InstallFixture::DIR

  before do
    skip 'set STAGE_A=1 to run (needs pnpm, Bun and the network)' unless ENV['STAGE_A']
    InstallFixture.roots
  end

  # A fresh copy of the fixture app for `manager`, ready for its first install.
  def app(manager)
    dir = File.join(BUNDLE, InstallFixture::APP)
    %w[.proscenium node_modules package.json pnpm-workspace.yaml pnpm-lock.yaml bun.lock yarn.lock
       bunfig.toml .gitignore].each { FileUtils.rm_rf(File.join(dir, it)) }
    package = { 'name' => 'app', 'private' => true,
                'dependencies' => { 'react' => '18.3.1', 'react-dom' => '18.3.1' } }
    if manager == 'bun'
      package['trustedDependencies'] = []
      File.write(File.join(dir, 'bunfig.toml'), "[install]\nlinker = \"isolated\"\n")
    else
      package['packageManager'] =
        "pnpm@#{Proscenium::CLI::Manager::CAPABILITIES.dig('managers', 'pnpm', 'lines', 0, 'ci')}"
    end
    File.write(File.join(dir, 'package.json'), "#{JSON.pretty_generate(package)}\n")
    dir
  end

  def proscenium(dir, *args, manager: nil, env: {})
    args += ['--manager', manager] if manager
    Bundler.with_unbundled_env do
      bundle_env = StageA::Bundle.env(BUNDLE, app: InstallFixture::APP).merge(env)
      Open3.capture3(bundle_env, RbConfig.ruby, '-I', LIB, EXE, *args, chdir: dir)
    end
  end

  def context(dir, gem) = File.join(dir, '.proscenium/packages', gem, 'package.json')

  %w[pnpm bun].each do |manager|
    describe manager do
      it 'registers, writes every context, installs, and is then up to date' do
        dir = app(manager)
        out, err, status = proscenium(dir, 'install', manager:)

        assert_predicate status, :success?, err
        assert_includes out, '+  - .proscenium/packages/*' if manager == 'pnpm'
        assert_includes out, '".proscenium/packages/*"' if manager == 'bun'
        assert_includes out,
                        "Installed JavaScript dependencies for #{GEMS.size} gems with #{manager}"
        GEMS.each { assert_path_exists context(dir, it) }
        refute_path_exists File.join(dir, '.proscenium/packages/stage_a_assets')
        refute_path_exists File.join(dir, '.proscenium/installing')
        assert_includes err, 'PSM-E-REACT' # hue's shape: React as a dependency is a warning

        bytes = GEMS.to_h { [it, File.binread(context(dir, it))] }
        out, err, status = proscenium(dir, 'install', manager:)

        assert_predicate status, :success?, err
        refute_includes out, '@@'
        assert_equal(bytes, GEMS.to_h { [it, File.binread(context(dir, it))] })

        out, err, status = proscenium(dir, 'install', '--frozen', manager:)

        assert_predicate status, :success?, err
        assert_includes out, "Everything is up to date for #{GEMS.size} gems."

        out, err, status = proscenium(dir, 'inspect', '--json')
        report = JSON.parse(out)

        assert_predicate status, :success?, err
        assert_equal manager, report.dig('manager', 'name')
        assert_equal(GEMS, report['gems'].map { it['gem'] })
        assert_equal ['current'], report['gems'].map { it['status'] }.uniq
        hue = report['gems'].find { it['gem'] == 'stage_a_hue_shape' }

        assert_match %r{\Ahttps?://|/stage_a_hue_shape}, hue['source']
        assert_equal ['escape-string-regexp@github:sindresorhus/escape-string-regexp#ba9a447'],
                     hue['gitAndUrl']

        File.write(context(dir, 'gem_npm'), '{}')
        out, = proscenium(dir, 'inspect', 'gem_npm')

        assert_includes out, 'gem_npm 1.0.0: context stale'

        File.write(context(dir, 'gem_npm'), bytes['gem_npm'].gsub('  ', '    '))
        out, = proscenium(dir, 'inspect', 'gem_npm')

        assert_includes out, 'gem_npm 1.0.0: context edited'
      end

      it 'refuses a package of its own in .proscenium/packages, and runs from a subdirectory' do
        dir = app(manager)
        FileUtils.mkdir_p(File.join(dir, '.proscenium/packages/mine'))
        File.write(File.join(dir, '.proscenium/packages/mine/package.json'), '{"name": "mine"}')
        _, err, status = proscenium(dir, 'install', manager:)

        assert_equal 2, status.exitstatus
        assert_includes err, 'PSM-E-OWNED-DIR'
        assert_path_exists File.join(dir, '.proscenium/packages/mine/package.json')

        FileUtils.rm_rf(File.join(dir, '.proscenium/packages/mine'))
        sub = File.join(dir, 'app', 'views')
        FileUtils.mkdir_p(sub)
        _, err, status = proscenium(sub, 'install', manager:)

        assert_predicate status, :success?, err
        assert_path_exists context(dir, 'stage_a_widget_a')
        refute_path_exists File.join(sub, '.proscenium')

        # C53: BUNDLE_GEMFILE names the app, and install runs from somewhere else entirely.
        Dir.mktmpdir('elsewhere') do |elsewhere|
          _, err, status = proscenium(elsewhere, 'install', '--frozen', manager:)

          assert_predicate status, :success?, err
          assert_empty Dir.children(elsewhere)
        end
      end

      # C11: two gems pin conflicting versions of one package. Each context keeps its own; nothing
      # flattens them to one.
      it 'keeps conflicting versions of one package in each gem\'s own context' do
        dir = app(manager)
        _, err, status = proscenium(dir, 'install', manager:)

        assert_predicate status, :success?, err
        versions = WIDGETS.to_h do |gem|
          manifest = File.join(dir, '.proscenium/packages', gem, 'node_modules/ms/package.json')
          [gem, JSON.parse(File.read(manifest))['version']]
        end

        assert_equal({ 'stage_a_widget_a' => '2.0.0', 'stage_a_widget_b' => '2.1.3' }, versions)
      end

      # C28: the gems are installed read-only, as a shared or system install is, and an install
      # writes nothing into them: no file added, removed or changed.
      it 'writes nothing into the installed gems' do
        gems = File.join(BUNDLE, 'bundle')
        snapshot = lambda do
          Dir.glob('**/*', File::FNM_DOTMATCH, base: gems).sort.to_h do |path|
            stat = File.lstat(File.join(gems, path))
            [path, [stat.size, stat.mtime.to_f]]
          end
        end
        before = snapshot.call
        dir = app(manager)
        _, err, status = proscenium(dir, 'install', manager:)

        assert_predicate status, :success?, err
        assert_equal before, snapshot.call

        # The positive control: a write into a gem root is one the snapshot sees.
        gem_dir = Dir.glob(File.join(gems, '**/gems/stage_a_widget_a-*')).first
        File.chmod(0o755, gem_dir)
        File.write(File.join(gem_dir, 'control'), '')

        refute_equal before, snapshot.call
      ensure
        if gem_dir
          File.delete(File.join(gem_dir, 'control'))
          File.chmod(0o555, gem_dir)
        end
      end

      # C32: a deploy without the development group trusts that gem's committed context, leaves
      # its dependencies out and needs no network.
      it 'installs for production without an excluded group, offline' do
        dir = app(manager)
        proscenium(dir, 'install', manager:)
        FileUtils.rm_rf(Dir[File.join(dir, '{,.proscenium/packages/*/}node_modules')])
        out, err, status = proscenium(dir, 'install', '--frozen', '--production', '--offline',
                                      manager:, env: { 'BUNDLE_WITHOUT' => 'development' })

        assert_predicate status, :success?, err
        assert_includes out, "Everything is up to date for #{GEMS.size - 1} gems."
        assert_includes out, 'gem_npm: not installed, its committed context kept'
        assert_path_exists context(dir, 'gem_npm')
        assert_path_exists File.join(dir, 'node_modules')
        refute_path_exists File.join(dir, '.proscenium/packages/gem_npm/node_modules/string-length')
      end

      # C29: install writes only inside .proscenium/, never through a link out of it.
      it 'refuses to write through a linked .proscenium/packages' do
        dir = app(manager)
        outside = Dir.mktmpdir('outside')
        FileUtils.mkdir_p(File.join(dir, '.proscenium'))
        begin
          File.symlink(outside, File.join(dir, '.proscenium/packages'))
        rescue NotImplementedError, Errno::EPERM, Errno::EACCES
          skip 'symlinks need privileges here'
        end
        _, err, status = proscenium(dir, 'install', manager:)

        assert_equal 2, status.exitstatus, err
        assert_includes err, 'PSM-E-OWNED-LINK'
        assert_empty Dir.children(outside)
      ensure
        link = dir && File.join(dir, '.proscenium/packages')
        if link && File.symlink?(link)
          begin
            File.unlink(link)
          rescue SystemCallError
            Dir.rmdir(link) # a directory link on Windows
          end
        end
        FileUtils.rm_rf(outside) if outside
      end

      it 'fails --frozen on a hand edit, an orphan or a missing registration, before the manager' do
        dir = app(manager)
        proscenium(dir, 'install', manager:)

        path = context(dir, 'stage_a_widget_a')
        edited = JSON.parse(File.read(path))
        edited['dependencies']['ms'] = '9.9.9'
        File.write(path, JSON.pretty_generate(edited))
        FileUtils.mkdir_p(File.join(dir, '.proscenium/packages/ghost'))
        _, err, status = proscenium(dir, 'install', '--frozen', manager:)

        assert_equal 4, status.exitstatus
        assert_includes err, 'stage_a_widget_a: its context was edited by hand'
        assert_includes err, '-    "ms": "9.9.9"'
        assert_includes err, 'ghost: its context belongs to no participating gem'

        _, err, status = proscenium(dir, 'install', manager:)

        assert_predicate status, :success?, err
        refute_path_exists File.join(dir, '.proscenium/packages/ghost')
      end
    end
  end

  # C34: a failed or interrupted install leaves the marker the engine refuses to build behind, and
  # running install again recovers.
  it 'leaves the install marker when the manager fails, and recovers on the next install' do
    dir = app('pnpm')
    _, err, status = proscenium(dir, 'install', '--js-arg', '--no-such-flag-for-pnpm')

    assert_equal 6, status.exitstatus, err
    assert_includes err, 'PSM-E-NATIVE'
    assert_path_exists File.join(dir, '.proscenium/installing')

    out, err, status = proscenium(dir, 'install')

    assert_predicate status, :success?, err
    assert_includes out, 'Finishing an interrupted install.'
    refute_path_exists File.join(dir, '.proscenium/installing')
  end

  it "refuses an app still depending on a gem's package itself, changing nothing (C05)" do
    dir = app('pnpm')
    package = JSON.parse(File.read(File.join(dir, 'package.json')))
    package['dependencies']['@rubygems/stage_a_hue_shape'] = 'github:harleytherapy/hue#22e6604'
    File.write(File.join(dir, 'package.json'), JSON.generate(package))
    before = Dir.children(dir).sort
    _, err, status = proscenium(dir, 'install')

    assert_equal 2, status.exitstatus
    assert_includes err, 'PSM-E-COLLISION'
    assert_includes err, '@rubygems/stage_a_hue_shape as "github:harleytherapy/hue#22e6604"'
    assert_equal before, Dir.children(dir).sort
  end

  # C27: an app reached through a UNC path, as from a network share. The admin share of the
  # runner's own drive stands in for one. The runner's pnpm is a .cmd shim, which cmd.exe cannot
  # run there, so the install is refused before the manager runs at all.
  it 'refuses a .cmd shim for an app reached through a UNC path on Windows' do
    skip 'UNC paths are Windows only' unless Gem.win_platform?

    dir = app('pnpm')
    _, err, status = proscenium(dir, 'install')

    assert_predicate status, :success?, err
    unc = ->(path) { "\\\\localhost\\#{path[0]}$#{path[2..].tr('/', '\\')}" }
    skip "no admin share here: #{unc.call(dir)}" unless File.directory?(unc.call(dir))

    _, err, status = proscenium(unc.call(dir), 'install', '--frozen',
                                env: { 'BUNDLE_GEMFILE' => unc.call(File.join(dir, 'Gemfile')) })

    assert_equal 3, status.exitstatus, err
    assert_includes err, 'PSM-E-UNC-SHIM'
  end

  it 'refuses Bun without an explicit linker, changing nothing' do
    dir = app('bun')
    File.delete(File.join(dir, 'bunfig.toml'))
    before = Dir.children(dir).sort
    _, err, status = proscenium(dir, 'install', manager: 'bun')

    assert_equal 3, status.exitstatus
    assert_includes err, 'PSM-E-BUN-LINKER'
    assert_equal before, Dir.children(dir).sort
  end

  it 'refuses a Yarn project, changing nothing' do
    dir = app('pnpm')
    File.write(File.join(dir, 'package.json'), '{"name": "app", "private": true}')
    File.write(File.join(dir, 'yarn.lock'), '')
    before = Dir.children(dir).sort
    _, err, status = proscenium(dir, 'install')

    assert_equal 3, status.exitstatus
    assert_includes err, 'PSM-E-UNSUPPORTED-MANAGER'
    assert_equal before, Dir.children(dir).sort
  ensure
    FileUtils.rm_f(File.join(dir, 'yarn.lock'))
  end

  it 'exits 7 while another install holds the lock' do
    dir = app('pnpm')
    FileUtils.mkdir_p(File.join(dir, '.proscenium'))
    File.open(File.join(dir, '.proscenium/lock'), File::RDWR | File::CREAT) do |io|
      io.flock(File::LOCK_EX)
      File.write(File.join(dir, '.proscenium/holder'), 'proscenium install (pid 1)')
      _, err, status = proscenium(dir, 'install')

      assert_equal 7, status.exitstatus
      assert_includes err, 'proscenium install (pid 1) is already running'
    end
  end
end
