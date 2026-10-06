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
  # C40: Proscenium's own share of an install. Calibrated on CI 2026-10-04 from the warm no-op
  # frozen install: Linux pnpm 741 ms / Bun 245, macOS 846 / 281, Windows 1385 / 609. The slowest
  # plus headroom. The cold and one-gem-changed installs are held to the same ceiling.
  OVERHEAD_BUDGET_MS = 2000
  # Each lock's recorded integrity for ms 2.1.3, up to the hash itself.
  TAMPER = { 'pnpm' => /(ms@2\.1\.3:\n\s+resolution: \{integrity: )sha512-[^}]+/,
             'bun' => /("ms@2\.1\.3", "", \{\}, ")sha512-[^"]+/ }.freeze
  BUNDLE = InstallFixture::DIR
  FOREIGN = ['{"name": "mine"}', '{"name": "mine", "proscenium": {}}'].freeze

  before do
    skip 'set STAGE_A=1 to run (needs pnpm, Bun and the network)' unless ENV['STAGE_A']
    InstallFixture.roots
  end

  # Removes `path` for certain. rm_rf ignores what it cannot delete, and on Windows it left a
  # Bun store behind, so a "fresh" app still had the last install's layout.
  def remove!(path)
    FileUtils.rm_rf(path)
    if File.exist?(path) && Gem.win_platform?
      system('cmd', '/c', 'rmdir', '/s', '/q', path.tr('/', '\\'), out: File::NULL, err: File::NULL)
    end
    raise "could not remove #{path}" if File.exist?(path)
  end

  # A fresh copy of the fixture app for `manager`, ready for its first install.
  def app(manager)
    dir = File.join(BUNDLE, InstallFixture::APP)
    %w[.proscenium node_modules package.json pnpm-workspace.yaml pnpm-lock.yaml bun.lock yarn.lock
       bunfig.toml .gitignore].each { remove!(File.join(dir, it)) }
    package = { 'name' => 'app', 'private' => true,
                'dependencies' => { 'react' => '18.3.1', 'react-dom' => '18.3.1' } }
    if manager == 'bun'
      package['trustedDependencies'] = []
      File.write(File.join(dir, 'bunfig.toml'), "[install]\nlinker = \"isolated\"\n")
    else
      package['packageManager'] = "pnpm@#{CLIHelper.pnpm_version}"
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

  def remove_node_modules(dir)
    FileUtils.rm_rf(Dir[File.join(dir, '{,.proscenium/packages/*/}node_modules')])
  end

  # Whether a native frozen Bun install succeeds in `dir`, from a clean tree.
  def native_bun_frozen(dir, env)
    remove_node_modules(dir)
    Bundler.with_unbundled_env do
      system(env, 'bun', 'install', '--frozen-lockfile', chdir: dir, out: File::NULL,
                                                         err: File::NULL)
    end
  end

  def context(dir, gem) = File.join(dir, '.proscenium/packages', gem, 'package.json')

  # Proscenium's own share of one `install` in milliseconds: its wall time less the manager's run.
  def overhead(dir, manager, label, *, env: {})
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out, err, status = proscenium(dir, 'install', *, '--json', manager:, env:)
    wall = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    assert_predicate status, :success?, err
    timings = out.lines.map { JSON.parse(it) }.find { %w[installed frozen].include?(it['event']) }
                 .dig('details', 'timings')
    overhead = wall - timings.fetch('manager')
    warn "C40 #{RUBY_PLATFORM} #{manager} #{label}: wall #{wall} ms, Proscenium #{overhead} ms, " \
         "phases #{timings}"
    overhead
  end

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
        assert_empty report['buildRefused']

        # Every reason the engine refuses to build, not only each gem's own context: an orphan.
        orphan = File.join(dir, '.proscenium/packages/gone/package.json')
        FileUtils.mkdir_p(File.dirname(orphan))
        File.write(orphan, '{"proscenium": {}}')
        out, = proscenium(dir, 'inspect')

        assert_includes out, "Rails will refuse to build assets until you fix:\n  - " \
                             "#{format(Proscenium::StaleContexts::ORPHAN, gem: 'gone')}"
        FileUtils.rm_rf(File.dirname(orphan))

        File.write(context(dir, 'gem_npm'), '{}')
        out, = proscenium(dir, 'inspect', 'gem_npm')

        assert_includes out, 'gem_npm 1.0.0: out of date'

        File.write(context(dir, 'gem_npm'), bytes['gem_npm'].gsub('  ', '    '))
        out, = proscenium(dir, 'inspect', 'gem_npm', '--quiet')

        assert_includes out, 'gem_npm 1.0.0: edited by hand', 'inspect --quiet still prints it'
      end

      # inspect names everything that stops the app working, and exits 4 when it finds any.
      it 'inspects the manager, registration, .gitignore, lockfile and install' do
        dir = app(manager)
        proscenium(dir, 'install', manager:)
        lockfile = manager == 'bun' ? 'bun.lock' : 'pnpm-lock.yaml'
        registrar = manager == 'bun' ? 'package.json' : 'pnpm-workspace.yaml'
        codes = lambda do
          out, err, status = proscenium(dir, 'inspect', '--json')

          [status.exitstatus, JSON.parse(out)['problems'].map { it['code'] }, err]
        end
        # Inspects with `file`'s text replaced by what the block returns, then restores it.
        swap = lambda do |file, &change|
          path = File.join(dir, file)
          before = File.read(path)
          File.write(path, change.call(before))
          codes.call
        ensure
          File.write(path, before) if before
        end

        out, err, status = proscenium(dir, 'inspect')

        assert_predicate status, :success?, err
        assert_includes out, 'No problems found.'

        File.write(File.join(dir, 'yarn.lock'), '')

        assert_equal [4, ['PSM-E-MANAGER-CONFLICT']], codes.call.first(2)
        File.delete(File.join(dir, 'yarn.lock'))

        assert_equal [4, ['PSM-E-GITIGNORE']],
                     swap.call('.gitignore') { "node_modules/\n" }.first(2)
        unregistered = swap.call(registrar) do |text|
          next '' if manager == 'pnpm'

          JSON.pretty_generate(JSON.parse(text).except('workspaces'))
        end

        assert_equal [4, ['PSM-E-NOT-REGISTERED']], unregistered.first(2)

        File.rename(File.join(dir, lockfile), File.join(dir, "#{lockfile}.bak"))

        # This Bun app names its manager only by bun.lock, so without it install cannot tell.
        missing = manager == 'bun' ? 'PSM-E-NO-MANAGER' : 'PSM-E-LOCKFILE-MISSING'

        assert_equal [4, [missing]], codes.call.first(2)
        File.rename(File.join(dir, "#{lockfile}.bak"), File.join(dir, lockfile))

        remove!(File.join(dir, 'node_modules'))
        out, = proscenium(dir, 'inspect')

        assert_equal [4, ['PSM-E-NOT-INSTALLED']], codes.call.first(2)
        assert_includes out, 'To fix: Run `bundle exec proscenium install`'
      end

      it 'refuses a package of its own in .proscenium/packages, and runs from a subdirectory' do
        dir = app(manager)
        FileUtils.mkdir_p(File.join(dir, '.proscenium/packages/mine'))
        # Nor is one that only has a `proscenium` key: install would delete it as an orphan.
        FOREIGN.each do |manifest|
          File.write(File.join(dir, '.proscenium/packages/mine/package.json'), manifest)
          _, err, status = proscenium(dir, 'install', manager:)

          assert_equal 2, status.exitstatus, manifest
          assert_includes err, 'PSM-E-OWNED-DIR'
          assert_path_exists File.join(dir, '.proscenium/packages/mine/package.json')
        end

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

      # C16: the app's policy is the root's, and reaches every context. An app-wide override of
      # ms replaces both widgets' pins; pnpm reads it from pnpm-workspace.yaml, Bun from
      # package.json.
      it "applies the app's own overrides to every gem's context" do
        dir = app(manager)
        if manager == 'pnpm'
          File.write(File.join(dir, 'pnpm-workspace.yaml'), "overrides:\n  ms: 2.1.2\n")
        else
          package = JSON.parse(File.read(File.join(dir, 'package.json')))
          File.write(File.join(dir, 'package.json'),
                     JSON.pretty_generate(package.merge('overrides' => { 'ms' => '2.1.2' })))
        end
        _, err, status = proscenium(dir, 'install', manager:)

        assert_predicate status, :success?, err
        versions = WIDGETS.map do |gem|
          manifest = File.join(dir, '.proscenium/packages', gem, 'node_modules/ms/package.json')
          JSON.parse(File.read(manifest))['version']
        end

        assert_equal %w[2.1.2 2.1.2], versions
      end

      # C30: the manager's own integrity check still guards every package a context installs. A
      # lock whose recorded hash for ms no longer matches the package fails a frozen install.
      # pnpm refuses such a lock on every host. Bun does on Linux and macOS, but on Windows it
      # installed one anyway, so for Bun the test holds Proscenium to whatever Bun does natively
      # on the same tampered tree.
      it 'keeps the manager\'s verdict on a lock that no longer matches a package' do
        dir = app(manager)
        _, err, status = proscenium(dir, 'install', manager:)

        assert_predicate status, :success?, err
        lock = File.join(dir, manager == 'pnpm' ? 'pnpm-lock.yaml' : 'bun.lock')
        text = File.read(lock)
        tampered = text.sub(TAMPER.fetch(manager)) { "#{Regexp.last_match(1)}sha512-AAAA" }

        refute_equal text, tampered, 'the lock had no integrity for ms to tamper with'
        File.write(lock, tampered)
        # A cold cache, so the package is fetched and checked. Measured: Bun with a warm cache
        # reuses a cached package without checking it against the lock, natively too.
        cache = Dir.mktmpdir('cold')
        cold = { 'BUN_INSTALL_CACHE_DIR' => cache }
        native = manager == 'bun' && native_bun_frozen(dir, cold)
        File.write(lock, tampered)
        remove_node_modules(dir)
        _, err, status = proscenium(dir, 'install', '--frozen', manager:, env: cold)

        assert_equal native ? 0 : 6, status.exitstatus, err
      ensure
        FileUtils.rm_rf(cache) if cache
      end

      # C40: what Proscenium adds to a native install, split by phase, and no frontend file
      # copied into a context. Printed on every host; the budget is the calibrated ceiling on
      # Proscenium's own share (everything but the manager's run) of a cold first install, with an
      # empty manager store, a no-op frozen install, and an install after one gem changed: its
      # context missing, as when the gem joins the bundle.
      it "keeps its own share of an install within #{OVERHEAD_BUDGET_MS} ms" do
        dir = app(manager)
        cache = Dir.mktmpdir('cold')
        env = {}
        if manager == 'pnpm'
          File.write(File.join(dir, 'pnpm-workspace.yaml'), "storeDir: #{cache.to_json}\n")
        else
          env['BUN_INSTALL_CACHE_DIR'] = cache
        end
        cold = overhead(dir, manager, 'cold', env:)
        noop = overhead(dir, manager, 'no-op', '--frozen', env:)
        remove!(File.dirname(context(dir, 'stage_a_widget_a')))
        changed = overhead(dir, manager, 'one gem changed', env:)

        assert_path_exists File.join(dir, '.proscenium/packages/stage_a_widget_a/node_modules/ms')
        assert_operator [cold, noop, changed].max, :<=, OVERHEAD_BUDGET_MS
        copied = Dir.glob('*/**/*', base: File.join(dir, '.proscenium/packages'))
                    .reject { it.include?('/node_modules') || File.basename(it) == 'package.json' }

        assert_empty copied, 'a context holds only its package.json'
      ensure
        remove!(cache) if cache
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
        assert_includes out, 'gem_npm is not installed here, so its committed dependency ' \
                             'context was kept'
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

      it 'fails --frozen on drift of every kind, before the manager' do
        dir = app(manager)
        proscenium(dir, 'install', manager:)

        path = context(dir, 'stage_a_widget_a')
        edited = JSON.parse(File.read(path))
        edited['dependencies']['ms'] = '9.9.9'
        File.write(path, JSON.pretty_generate(edited))
        FileUtils.mkdir_p(File.join(dir, '.proscenium/packages/ghost'))
        _, err, status = proscenium(dir, 'install', '--frozen', manager:)

        assert_equal 4, status.exitstatus
        assert_includes err, 'stage_a_widget_a: its dependency context was edited by hand'
        assert_includes err, '-    "ms": "9.9.9"'
        assert_includes err, format(Proscenium::StaleContexts::ORPHAN, gem: 'ghost')

        _, err, status = proscenium(dir, 'install', manager:)

        assert_predicate status, :success?, err
        refute_path_exists File.join(dir, '.proscenium/packages/ghost')

        # A context written by an older projection, and one deleted outright.
        path = context(dir, 'stage_a_widget_a')
        older = JSON.parse(File.read(path))
        older['proscenium']['projection'] = 'dependency-context-v0'
        File.write(path, JSON.pretty_generate(older))
        File.delete(context(dir, 'stage_a_widget_b'))
        _, err, status = proscenium(dir, 'install', '--frozen', manager:)

        assert_equal 4, status.exitstatus, err
        assert_includes err, 'stage_a_widget_a: its dependency context was written by a ' \
                             'different version of Proscenium'
        assert_includes err, "stage_a_widget_b: its dependency context hasn't been written yet"

        # The registration and the lockfile gone.
        proscenium(dir, 'install', manager:)
        unregister(dir, manager)
        File.delete(File.join(dir, manager == 'pnpm' ? 'pnpm-lock.yaml' : 'bun.lock'))
        _, err, status = proscenium(dir, 'install', '--frozen', manager:)

        assert_equal 4, status.exitstatus, err
        assert_includes err, 'the gem contexts are not registered'
        assert_includes err, "#{manager == 'pnpm' ? 'pnpm-lock.yaml' : 'bun.lock'} is missing"
      end
    end
  end

  # Takes .proscenium/packages/* back out of the manager's workspaces.
  def unregister(dir, manager)
    if manager == 'pnpm'
      File.write(File.join(dir, 'pnpm-workspace.yaml'), "packages: []\n")
    else
      path = File.join(dir, 'package.json')
      package = JSON.parse(File.read(path))
      package['workspaces'] -= ['.proscenium/packages/*']
      File.write(path, JSON.generate(package))
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
    assert_includes out, 'Finishing an install that was stopped before it finished.'
    refute_path_exists File.join(dir, '.proscenium/installing')
  end

  # Install removes only what it owns: a folder that holds nothing but an old context's
  # node_modules is an orphan, but one with anything else in it is someone's, and is refused.
  it 'removes an orphaned node_modules, but refuses a folder of its own in .proscenium/packages' do
    dir = app('pnpm')
    orphan = File.join(dir, '.proscenium/packages/gone/node_modules')
    FileUtils.mkdir_p(orphan)
    # An interrupted write, and the dotfiles an OS leaves, are not the user's either.
    File.write(File.join(dir, '.proscenium/packages/gone/package.json.tmp'), '{')
    File.write(File.join(dir, '.proscenium/packages/gone/.DS_Store'), '')
    _, err, status = proscenium(dir, 'install', manager: 'pnpm')

    assert_predicate status, :success?, err
    refute_path_exists File.dirname(orphan)

    # A file of the user's, or a dotfile such as a nested repository's .git, is not removed.
    ['.proscenium/packages/mine/notes.txt', '.proscenium/packages/repo/.git/HEAD'].each do |path|
      notes = File.join(dir, path)
      FileUtils.mkdir_p(File.dirname(notes))
      File.write(notes, 'keep me')
      _, err, status = proscenium(dir, 'install', manager: 'pnpm')

      assert_equal 2, status.exitstatus, err
      assert_includes err, 'PSM-E-OWNED-DIR'
      assert_path_exists notes
      FileUtils.rm_rf(File.join(dir, path.split('/').first(3).join('/')))
    end

    # A file or a dangling link in place of a context directory is the user's too, refused before
    # anything is written, even where a gem's context would go.
    File.write(File.join(dir, '.proscenium/packages/.DS_Store'), '')
    { 'stage_a_widget_a' => -> { File.write(it, 'keep me') },
      'dangling' => -> { File.symlink(File.join(dir, 'nowhere'), it) } }.each do |name, make|
      path = File.join(dir, '.proscenium/packages', name)
      FileUtils.rm_rf(path)
      begin
        make.call(path)
      rescue NotImplementedError, Errno::EPERM, Errno::EACCES
        next # symlinks need privileges here
      end
      _, err, status = proscenium(dir, 'install', manager: 'pnpm')

      assert_equal 2, status.exitstatus, err
      assert_includes err, 'PSM-E-OWNED-DIR'
      assert_includes err, name
      refute_path_exists File.join(dir, '.proscenium/installing')
      File.delete(path)
    end
  end

  # A registration install cannot write is refused before the install marker: nothing has changed,
  # so the engine must not go on refusing every build.
  it 'refuses a package.json it cannot register, leaving no install marker' do
    dir = app('bun')
    package = JSON.parse(File.read(File.join(dir, 'package.json')))
    File.write(File.join(dir, 'package.json'),
               JSON.generate(package.merge('workspaces' => { 'nohoist' => ['x'] })))
    before = File.read(File.join(dir, 'package.json'))
    _, err, status = proscenium(dir, 'install', manager: 'bun')

    assert_equal 2, status.exitstatus, err
    assert_includes err, 'PSM-E-REGISTRATION'
    refute_path_exists File.join(dir, '.proscenium/installing')
    assert_equal before, File.read(File.join(dir, 'package.json'))
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

  # C48: a Bun app that sets no linker gets the one it uses today written with the registration,
  # here hoisted, as nothing is installed and the app declares no workspaces of its own. A frozen
  # install writes nothing, so it still refuses.
  it 'writes the Bun linker the app uses today, and refuses one frozen without it' do
    dir = app('bun')
    File.delete(File.join(dir, 'bunfig.toml'))
    before = Dir.children(dir).sort
    _, err, status = proscenium(dir, 'install', '--frozen', manager: 'bun')

    assert_equal 3, status.exitstatus
    assert_includes err, 'PSM-E-BUN-LINKER'
    assert_equal before, Dir.children(dir).sort

    out, err, status = proscenium(dir, 'install', manager: 'bun')

    assert_predicate status, :success?, err
    assert_includes out, '+linker = "hoisted"'
    assert_equal "[install]\nlinker = \"hoisted\"\n", File.read(File.join(dir, 'bunfig.toml'))
    refute_path_exists File.join(dir, 'node_modules/.bun')
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

  # A frozen install runs the manager too, so it waits its turn like any other: two managers in
  # one node_modules at once corrupt it.
  it 'exits 7 while another install holds the lock, frozen or not' do
    dir = app('pnpm')
    _, err, status = proscenium(dir, 'install', manager: 'pnpm')

    assert_predicate status, :success?, err
    File.open(File.join(dir, '.proscenium/lock'), File::RDWR | File::CREAT) do |io|
      io.flock(File::LOCK_EX)
      File.write(File.join(dir, '.proscenium/holder'), 'proscenium install (pid 1)')
      [%w[install], %w[install --frozen]].each do |args|
        _, err, status = proscenium(dir, *args)

        assert_equal 7, status.exitstatus, args.join(' ')
        assert_includes err, 'proscenium install (pid 1) is already running'
      end

      # A frozen install reads for drift under the lock too: the install holding it may be
      # rewriting the very contexts it would compare.
      File.delete(context(dir, 'stage_a_widget_a'))
      _, err, status = proscenium(dir, 'install', '--frozen')

      assert_equal 7, status.exitstatus, err
    end
  end
end
