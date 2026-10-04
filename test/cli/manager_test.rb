# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'proscenium/cli/manager'

# Manager selection, the capability table and Bun's registration preconditions (#154, C07, C51).
describe Proscenium::CLI::Manager do
  M = Proscenium::CLI::Manager

  before { @dir = Dir.mktmpdir('manager') }
  after { FileUtils.rm_rf(@dir) }

  def write(path, body = '')
    FileUtils.mkdir_p(File.dirname(File.join(@dir, path)))
    File.write(File.join(@dir, path), body)
  end

  def code(&) = assert_raises(Proscenium::CLI::Error, &).code

  describe 'selection' do
    it 'takes the lockfile when it is the only signal' do
      write('pnpm-lock.yaml')

      assert_equal 'pnpm', M.select(@dir).name
      FileUtils.rm(File.join(@dir, 'pnpm-lock.yaml'))
      write('bun.lock')

      assert_equal 'bun', M.select(@dir).name
    end

    it 'takes packageManager, then --manager over it' do
      write('package.json', '{"packageManager": "pnpm@11.28.4+sha512.abc"}')

      assert_equal 'pnpm', M.select(@dir).name
      assert_equal 'bun', M.select(@dir, requested: 'bun').name
    end

    it 'refuses conflicting signals' do
      write('pnpm-lock.yaml')
      write('bun.lock')

      assert_equal('PSM-E-MANAGER-CONFLICT', code { M.select(@dir) })
    end

    it 'refuses a packageManager that disagrees with the lockfile' do
      write('package.json', '{"packageManager": "bun@1.4.2"}')
      write('pnpm-lock.yaml')

      assert_equal('PSM-E-MANAGER-CONFLICT', code { M.select(@dir) })
    end

    it 'refuses Yarn and npm projects, by any signal' do
      { 'yarn.lock' => 'yarn', '.yarnrc.yml' => 'yarn', 'package-lock.json' => 'npm',
        'npm-shrinkwrap.json' => 'npm' }.each do |file, manager|
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, file), '')
          error = assert_raises(Proscenium::CLI::Error) { M.select(dir) }

          assert_equal ['PSM-E-UNSUPPORTED-MANAGER', 3], [error.code, error.exit_status]
          assert_includes error.message, manager
        end
      end
      write('package.json', '{"packageManager": "yarn@4.0.0"}')

      assert_equal('PSM-E-UNSUPPORTED-MANAGER', code { M.select(@dir) })
    end

    it 'refuses a binary bun.lockb on its own' do
      write('bun.lockb')

      assert_equal('PSM-E-BUN-LOCKB', code { M.select(@dir) })
    end

    it 'asks for --manager when nothing says' do
      assert_equal('PSM-E-NO-MANAGER', code { M.select(@dir) })
    end
  end

  describe 'versions' do
    # A fake manager on PATH that prints `version`.
    def with_manager(name, version)
      bin = File.join(@dir, 'bin')
      FileUtils.mkdir_p(bin)
      if Gem.win_platform?
        File.write(File.join(bin, "#{name}.cmd"), "@echo #{version}\r\n")
      else
        File.write(File.join(bin, name), "#!/bin/sh\necho #{version}\n")
        FileUtils.chmod(0o755, File.join(bin, name))
      end
      path = ENV.fetch('PATH', nil)
      ENV['PATH'] = [bin, path].join(File::PATH_SEPARATOR)
      yield M.new(name, @dir)
    ensure
      ENV['PATH'] = path
    end

    it 'accepts every line in the capability table' do
      M::CAPABILITIES['managers'].each do |name, manager|
        manager['lines'].each do |line|
          with_manager(name, line['ci']) { assert_equal line, it.check_version!.line }
        end
      end
    end

    it 'warns within six months of a line reaching end of life' do
      with_manager('pnpm', '11.28.4') do |manager|
        manager.check_version!

        assert_nil manager.end_of_life_warning(today: Date.new(2026, 10, 4))
        assert_equal 'PSM-W-END-OF-LIFE',
                     manager.end_of_life_warning(today: Date.new(2026, 12, 1)).code
      end
    end

    it 'refuses pnpm 10, which is not supported' do
      with_manager('pnpm', '10.34.4') do |manager|
        assert_equal('PSM-E-MANAGER-VERSION', code { manager.check_version! })
      end
    end

    it 'refuses an unqualified version, unless experimental and not frozen' do
      with_manager('pnpm', '9.15.0') do |manager|
        error = assert_raises(Proscenium::CLI::Error) { manager.check_version! }

        assert_equal ['PSM-E-MANAGER-VERSION', 3], [error.code, error.exit_status]
        assert_same manager, manager.check_version!(experimental: true)
        assert_equal('PSM-E-EXPERIMENTAL-FROZEN',
                     code { manager.check_version!(experimental: true, frozen: true) })
      end
    end

    # C53: on Windows pnpm and Bun install as `.cmd` shims, which only PATHEXT names.
    it 'finds a .cmd shim through PATHEXT' do
      path = ENV.fetch('PATH', nil)
      pathext = ENV.fetch('PATHEXT', nil)
      write('bin/pnpm.cmd', "@echo off\r\n")
      File.chmod(0o755, File.join(@dir, 'bin/pnpm.cmd'))
      ENV['PATH'] = File.join(@dir, 'bin')
      ENV['PATHEXT'] = '.COM;.EXE;.BAT;.CMD'

      assert_equal File.join(@dir, 'bin', 'pnpm.cmd'), M.which('pnpm')
    ensure
      ENV['PATH'] = path
      ENV['PATHEXT'] = pathext
    end

    it 'says when the manager is not installed' do
      path = ENV.fetch('PATH', nil)
      ENV['PATH'] = @dir

      assert_equal('PSM-E-MANAGER-MISSING', code { M.new('pnpm', @dir).check_version! })
    ensure
      ENV['PATH'] = path
    end
  end

  describe 'Bun preconditions' do
    def bun = M.new('bun', @dir)

    it 'needs an explicit linker and trustedDependencies' do
      write('package.json', '{"trustedDependencies": []}')

      assert_equal('PSM-E-BUN-LINKER', code { bun.check_project! })
      write('bunfig.toml',
            "[install.scopes]\nx = 1\n\n[install]\n# a comment\nlinker = 'isolated' # yes\n")
      write('package.json', '{}')

      assert_equal('PSM-E-BUN-TRUSTED', code { bun.check_project! })
      write('package.json', '{"trustedDependencies": []}')

      assert_same bun.class, bun.check_project!.class
      assert_equal 'isolated', bun.bun_linker
    end

    it 'ignores a linker outside the [install] table' do
      write('bunfig.toml', "linker = \"hoisted\"\n[test]\nlinker = \"hoisted\"\n")

      assert_nil bun.bun_linker
    end
  end

  it 'refuses an app inside an enclosing JS workspace' do
    app = File.join(@dir, 'apps', 'rails')
    FileUtils.mkdir_p(app)
    write('package.json', '{"workspaces": ["apps/*"]}')

    assert_equal('PSM-E-NESTED-WORKSPACE', code { M.new('pnpm', app).check_project! })
    FileUtils.rm(File.join(@dir, 'package.json'))
    write('pnpm-workspace.yaml', "packages:\n  - apps/*\n")

    assert_equal('PSM-E-NESTED-WORKSPACE', code { M.new('pnpm', app).check_project! })
  end
end
