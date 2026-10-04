# frozen_string_literal: true

require_relative 'helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../package_manager/stage_a/bundle'

# The fixture bundle, installed once for every class in this file: nested `describe`s are classes
# of their own, so a class-level memo would install it again for each.
module InstallFixture
  DIR = Dir.mktmpdir('cli_install')
  Minitest.after_run do
    StageA::Bundle.writable!(DIR)
    FileUtils.rm_rf(DIR)
  end

  def self.roots = @roots ||= StageA::Bundle.install(DIR)
end

# `proscenium install` and `install --frozen`, end to end: the Stage A fixture gems, genuinely
# installed by Bundler, an app on pnpm or Bun, and the real manager (#154, Gate B rows).
#
# Runs only with STAGE_A=1: it needs pnpm, Bun and the network. The stage-a CI job sets it.
describe 'proscenium install' do
  LIB = File.expand_path('../../lib', __dir__)
  EXE = File.expand_path('../../exe/proscenium', __dir__)
  GEMS = %w[gem_npm stage_a_hue_shape stage_a_widget_a stage_a_widget_b].freeze
  BUNDLE = InstallFixture::DIR

  before do
    skip 'set STAGE_A=1 to run (needs pnpm, Bun and the network)' unless ENV['STAGE_A']
    InstallFixture.roots
  end

  # A fresh copy of the fixture app for `manager`, ready for its first install.
  def app(manager)
    dir = File.join(BUNDLE, 'app')
    %w[.proscenium node_modules package.json pnpm-workspace.yaml pnpm-lock.yaml bun.lock yarn.lock
       bunfig.toml .gitignore].each { FileUtils.rm_rf(File.join(dir, it)) }
    package = { 'name' => 'app', 'private' => true,
                'dependencies' => { 'react' => '18.3.1', 'react-dom' => '18.3.1' } }
    if manager == 'bun'
      package['trustedDependencies'] = []
      File.write(File.join(dir, 'bunfig.toml'), "[install]\nlinker = \"isolated\"\n")
    else
      package['packageManager'] = 'pnpm@10.33.1'
    end
    File.write(File.join(dir, 'package.json'), "#{JSON.pretty_generate(package)}\n")
    dir
  end

  def proscenium(dir, *args, manager: nil)
    args += ['--manager', manager] if manager
    Bundler.with_unbundled_env do
      Open3.capture3(StageA::Bundle.env(BUNDLE), RbConfig.ruby, '-I', LIB, EXE, *args, chdir: dir)
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
      io.write('proscenium install (pid 1)')
      io.flush
      _, err, status = proscenium(dir, 'install')

      assert_equal 7, status.exitstatus
      assert_includes err, 'proscenium install (pid 1) is already running'
    end
  end
end
