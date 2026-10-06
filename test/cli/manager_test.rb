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

    # Another lockfile is still another manager's, whichever one packageManager or --manager names.
    it 'refuses two lockfiles even when a manager is named' do
      write('package.json', '{"packageManager": "pnpm@11.28.4"}')
      write('pnpm-lock.yaml')
      write('bun.lock')

      assert_equal('PSM-E-MANAGER-CONFLICT', code { M.select(@dir) })
      assert_equal('PSM-E-MANAGER-CONFLICT', code { M.select(@dir, requested: 'bun') })
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

    it 'refuses a binary bun.lockb on its own, however Bun is chosen' do
      write('bun.lockb')

      assert_equal('PSM-E-BUN-LOCKB', code { M.select(@dir) })
      assert_equal('PSM-E-BUN-LOCKB', code { M.select(@dir, requested: 'bun') })
      write('package.json', '{"packageManager": "bun@1.4.2"}')

      assert_equal('PSM-E-BUN-LOCKB', code { M.select(@dir) })
      write('bun.lock')

      assert_equal 'bun', M.select(@dir).name
      File.delete(File.join(@dir, 'bun.lock'))
      File.delete(File.join(@dir, 'package.json'))

      # A Bun lock all the same, whichever manager is asked for.
      assert_equal('PSM-E-MANAGER-CONFLICT', code { M.select(@dir, requested: 'pnpm') })
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

    # The manager runs in the project root, so a relative PATH entry must name it absolutely.
    it 'finds a manager through a relative PATH entry as an absolute path' do
      skip 'the fake manager is a shell script' if Gem.win_platform?

      write('bin/pnpm', "#!/bin/sh\n")
      File.chmod(0o755, File.join(@dir, 'bin/pnpm'))
      found = Dir.chdir(@dir) { with_path('bin') { M.which('pnpm') } }

      assert_equal File.join(File.realpath(@dir), 'bin', 'pnpm'), File.realpath(found)
      assert_equal found, File.expand_path(found, '/elsewhere')
    end

    # C27: cmd.exe cannot run in a UNC directory, so a shim is refused there before it runs.
    it 'refuses a .cmd shim for a project reached through a UNC path' do
      path = ENV.fetch('PATH', nil)
      pathext = ENV.fetch('PATHEXT', nil)
      write('bin/pnpm.cmd', "@echo off\r\n")
      File.chmod(0o755, File.join(@dir, 'bin/pnpm.cmd'))
      ENV['PATH'] = File.join(@dir, 'bin')
      ENV['PATHEXT'] = '.COM;.EXE;.BAT;.CMD'

      %w[//server/share/app \\\\server\\share\\app].each do |root|
        assert_equal('PSM-E-UNC-SHIM', code { M.new('pnpm', root).check_version! })
      end
      refute M.unc?('D:/app')
    ensure
      ENV['PATH'] = path
      ENV['PATHEXT'] = pathext
    end

    # A fake pnpm on PATH that leaves a marker when run, for the duration of the block.
    def with_fake_pnpm
      path = ENV.fetch('PATH', nil)
      write('bin/pnpm', "#!/bin/sh\ntouch \"#{@dir}/ran\"\necho 11.28.4\n")
      write('bin/pnpm.cmd', "@echo off\r\necho 11.28.4\r\n") # found on Windows, never run
      File.chmod(0o755, File.join(@dir, 'bin/pnpm'))
      ENV['PATH'] = File.join(@dir, 'bin')
      yield
    ensure
      ENV['PATH'] = path
    end

    # pnpm 12 writes pnpm-lock.yaml on any command in a project that pins it, `--version` included,
    # so the pinned version is read from package.json, and the manager is not run.
    it 'reads a pinned version without running the manager' do
      write('package.json', '{"packageManager": "pnpm@12.9.1+sha512.abc"}')
      with_fake_pnpm do
        assert_equal '12.9.1', M.new('pnpm', @dir).check_version!.version
      end

      refute_path_exists File.join(@dir, 'ran')
    end

    # pmOnFail warn or ignore runs the installed pnpm whatever the pin says (pnpm 11's settings),
    # and then --version writes nothing; download, the default, or error runs only the pin.
    it 'asks pnpm for its version when pmOnFail lets it run unpinned' do
      skip 'the fake manager is a shell script' if Gem.win_platform?

      write('package.json', '{"packageManager": "pnpm@12.9.1"}')
      with_fake_pnpm do
        write('pnpm-workspace.yaml', "pmOnFail: ignore\n")

        assert_equal '11.28.4', M.new('pnpm', @dir).check_version!.version
        write('pnpm-workspace.yaml', "pmOnFail: error\n")

        assert_equal '12.9.1', M.new('pnpm', @dir).check_version!.version
        ENV['pnpm_config_pm_on_fail'] = 'warn'

        assert_equal '11.28.4', M.new('pnpm', @dir).check_version!.version
        # pnpm reads the uppercase form as well, ahead of the lowercase one.
        ENV['PNPM_CONFIG_PM_ON_FAIL'] = 'error'

        assert_equal '12.9.1', M.new('pnpm', @dir).check_version!.version
        ENV.delete('pnpm_config_pm_on_fail')
        ENV['PNPM_CONFIG_PM_ON_FAIL'] = 'ignore'

        assert_equal '11.28.4', M.new('pnpm', @dir).check_version!.version
      ensure
        ENV.delete('pnpm_config_pm_on_fail')
        ENV.delete('PNPM_CONFIG_PM_ON_FAIL')
      end
    end

    # GHSA-5wx6-mg75-v57r: pnpm 11.0.0 to 11.5.2 let a package spoofing an approved name in its
    # manifest run its build scripts, which no check of a gem's dependencies can see.
    it 'refuses pnpm 11 before 11.11.0' do
      skip 'the fake manager is a shell script' if Gem.win_platform?

      with_fake_pnpm do
        write('package.json', '{"packageManager": "pnpm@11.5.2"}')

        assert_equal('PSM-E-MANAGER-VERSION', code { M.new('pnpm', @dir).check_version! })
        # GHSA-vq4v-j7r6-jq4m: before 11.11.0 a tarball's manifest name could write outside
        # node_modules, scripts or not.
        write('package.json', '{"packageManager": "pnpm@11.10.9"}')

        assert_equal('PSM-E-MANAGER-VERSION', code { M.new('pnpm', @dir).check_version! })
        write('package.json', '{"packageManager": "pnpm@11.11.0"}')

        assert_equal '11.11.0', M.new('pnpm', @dir).check_version!.version
      end
    end

    # A prerelease is not the stable line it precedes or follows: it needs
    # --experimental-manager-version, which --frozen never allows.
    it 'refuses a prerelease manager unless experimental' do
      skip 'the fake manager is a shell script' if Gem.win_platform?

      with_fake_pnpm do
        %w[12.0.0-beta.1 13.0.0-rc.0].each do |version|
          write('package.json', JSON.generate('packageManager' => "pnpm@#{version}"))

          pnpm = M.new('pnpm', @dir)

          assert_equal('PSM-E-MANAGER-VERSION', code { pnpm.check_version! }, version)
          assert_equal version, pnpm.check_version!(experimental: true).version
          assert_equal('PSM-E-EXPERIMENTAL-FROZEN',
                       code { pnpm.check_version!(experimental: true, frozen: true) })
        end
        write('package.json', '{"packageManager": "pnpm@12.9.1+sha512.abc"}')

        assert_equal '12.9.1', M.new('pnpm', @dir).check_version!.version
      end
    end

    # Bun ignores packageManager and runs whatever is installed, so its pin proves nothing.
    it 'asks Bun for its version even when packageManager pins one' do
      skip 'the fake manager is a shell script' if Gem.win_platform?

      write('package.json', '{"packageManager": "bun@1.0.0"}')
      write('bin/bun', "#!/bin/sh\necho 1.4.2\n")
      File.chmod(0o755, File.join(@dir, 'bin/bun'))
      with_path(File.join(@dir, 'bin')) do
        assert_equal '1.4.2', M.new('bun', @dir).check_version!.version
      end
    end

    def with_path(dirs)
      path = ENV.fetch('PATH', nil)
      ENV['PATH'] = dirs
      yield
    ensure
      ENV['PATH'] = path
    end

    it 'asks the manager when nothing pins it' do
      skip 'the fake manager is a shell script' if Gem.win_platform?

      write('package.json', '{}')
      with_fake_pnpm do
        assert_equal '11.28.4', M.new('pnpm', @dir).check_version!.version
      end

      assert_path_exists File.join(@dir, 'ran')
    end

    # The first run of a pinned pnpm prints that it is downloading it, before the version.
    it 'reads the version past a download notice' do
      notice = '! Corepack is about to download https://registry.npmjs.org/pnpm/-/pnpm-12.9.1.tgz' \
               "\n" \
               "Downloading the pnpm 12.9.1 binary for darwin-arm64...\n12.9.1\n"

      assert_equal '12.9.1', M.version_in(notice)
      assert_equal '1.4.2', M.version_in("1.4.2\n")
      assert_equal 'not a version', M.version_in("not a version\n")
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

    # Install writes a missing linker (C48); only --frozen, which writes nothing, refuses it.
    it 'needs a linker for a frozen install, and no trustedDependencies' do
      write('package.json', '{"trustedDependencies": []}')

      assert_same bun.class, bun.check_project!.class
      assert_equal('PSM-E-BUN-LINKER', code { bun.check_project!(frozen: true) })
      write('bunfig.toml', "[install]\nlinker = \"nested\"\n")

      assert_equal('PSM-E-BUN-LINKER', code { bun.check_project! })
      write('bunfig.toml',
            "[install.scopes]\nx = 1\n\n[install]\n# a comment\nlinker = 'isolated' # yes\n")
      write('package.json', '{}')

      assert_same bun.class, bun.check_project!.class
      assert_equal 'isolated', bun.bun_linker
      # A # inside a TOML string is part of it, not a comment.
      write('bunfig.toml', "[install]\nlinker = \"isolated#x\" # mine\n")

      assert_equal 'isolated#x', bun.bun_linker
      assert_equal('PSM-E-BUN-LINKER', code { bun.check_project! })
    end

    # Valid TOML Bun honors: a quoted table name, a dotted key and an inline table.
    it 'reads the linker however bunfig.toml spells the install table' do
      { "[\"install\"]\nlinker = \"isolated\"\n" => 'isolated',
        "[ 'install' ]\nlinker = 'hoisted'\n" => 'hoisted',
        "install.linker = \"isolated\"\n" => 'isolated',
        "install = { exact = true, linker = \"hoisted\" }\n" => 'hoisted',
        "[install]\n\"linker\" = \"isolated\"\n" => 'isolated',
        "install.'linker' = 'hoisted'\n" => 'hoisted' }.each do |text, linker|
        write('bunfig.toml', text)

        assert_equal linker, bun.bun_linker, text
      end
    end

    # Registration could only add a second install table, which Bun refuses as a redefinition.
    it 'refuses an install table set inline without a linker' do
      write('package.json', '{"trustedDependencies": []}')
      ["install.exact = true\n", "install = { exact = true }\n"].each do |text|
        write('bunfig.toml', text)

        assert_equal('PSM-E-BUN-LINKER', code { bun.check_project! })
      end
    end

    # Bun reads a trailing comma; Proscenium cannot, so it says so rather than crash.
    it 'refuses a package.json that is not strict JSON' do
      write('bunfig.toml', "[install]\nlinker = \"isolated\"\n")
      write('package.json', '{"trustedDependencies": [],}')

      assert_equal('PSM-E-REGISTRATION', code { bun.check_project! })
    end

    # Without trustedDependencies, Bun trusts its own default list, which the installed Bun prints.
    it "takes the app's trusted names, or Bun's default list without any" do
      skip 'needs bun' unless M.which('bun')

      write('package.json', '{"trustedDependencies": ["mine"]}')

      assert_equal %w[mine], bun.check_version!(experimental: true).trusted_names
      write('package.json', '{}')
      defaults = bun.check_version!(experimental: true).trusted_names

      assert_includes defaults, 'esbuild'
      refute_includes defaults, 'mine'
    end

    # pnpm approves builds by name in pnpm-workspace.yaml: allowBuilds (a name, or a name at a
    # version), and the older onlyBuiltDependencies.
    it 'takes the names a pnpm app approves builds for' do
      yaml = "allowBuilds:\n  esbuild: true\n  '@img/sharp@0.33.0': true\n  nope: false\n" \
             "onlyBuiltDependencies:\n  - canvas\n"
      write('pnpm-workspace.yaml', yaml)

      assert_equal %w[esbuild @img/sharp canvas], M.new('pnpm', @dir).trusted_names
      # pnpm resolves an alias, for the approval, the name or the list entry alike.
      aliased = "on: &yes true\nname: &n sharp\nallowBuilds:\n  esbuild: *yes\n  *n : true\n" \
                "onlyBuiltDependencies:\n  - *n\n"
      write('pnpm-workspace.yaml', aliased)

      assert_equal %w[esbuild sharp], M.new('pnpm', @dir).trusted_names
      # And merge keys: inherited approvals count, and the mapping's own key overrides one.
      merged = "base: &base\n  esbuild: true\n  sharp: true\nallowBuilds:\n  <<: *base\n  " \
               "sharp: false\n"
      write('pnpm-workspace.yaml', merged)

      assert_equal %w[esbuild], M.new('pnpm', @dir).trusted_names
      # A YAML boolean in any of the core schema's spellings; a quoted 'true' is a string.
      write('pnpm-workspace.yaml', "allowBuilds:\n  a: TRUE\n  b: True\n  c: 'true'\n")

      assert_equal %w[a b], M.new('pnpm', @dir).trusted_names
      # An approval for an opaque locator approves its package name, whatever follows the @.
      write('pnpm-workspace.yaml', "allowBuilds:\n  'foo@https://host/pkg@1.0.0': true\n  " \
                                   "'@img/sharp@npm:other@1': true\n")

      assert_equal %w[foo @img/sharp], M.new('pnpm', @dir).trusted_names
      # The earlier of several merged mappings wins, and a mapping merging itself ends.
      several = "a: &a\n  esbuild: true\nb: &b\n  esbuild: false\n  sharp: true\n" \
                "allowBuilds: &self\n  <<: [*a, *b, *self]\n"
      write('pnpm-workspace.yaml', several)

      assert_equal %w[esbuild sharp], M.new('pnpm', @dir).trusted_names
      File.delete(File.join(@dir, 'pnpm-workspace.yaml'))

      assert_empty M.new('pnpm', @dir).trusted_names
      # And merges at the document's root (probed on pnpm 11.28.4 and 12.9.1), where a key of the
      # root's own overrides the merged one.
      write('pnpm-workspace.yaml', "defaults: &d\n  allowBuilds:\n    esbuild: true\n  " \
                                   "onlyBuiltDependencies: [sharp]\n<<: *d\n")

      assert_equal %w[esbuild sharp], M.new('pnpm', @dir).trusted_names
      write('pnpm-workspace.yaml', "defaults: &d\n  allowBuilds:\n    esbuild: true\n<<: *d\n" \
                                   "allowBuilds:\n  canvas: true\n")

      assert_equal %w[canvas], M.new('pnpm', @dir).trusted_names
      # pnpm follows merges however deep; only a cycle ends them.
      chain = (1..18).map { "l#{it}: &l#{it}\n  <<: *l#{it - 1}\n" }.join
      write('pnpm-workspace.yaml', "l0: &l0\n  esbuild: true\n#{chain}allowBuilds:\n  <<: *l18\n")

      assert_equal %w[esbuild], M.new('pnpm', @dir).trusted_names
    end

    # dangerouslyAllowAllBuilds approves every package's build, whatever its name: pnpm 11 and 12
    # read it from pnpm-workspace.yaml and the environment.
    it 'trusts every name when pnpm allows every build' do
      xdg_was = ENV.fetch('XDG_CONFIG_HOME', nil)
      write('pnpm-workspace.yaml', "dangerouslyAllowAllBuilds: true\n")

      assert_equal :all, M.new('pnpm', @dir).trusted_names
      write('pnpm-workspace.yaml', "dangerouslyAllowAllBuilds: 'true'\n")

      assert_empty M.new('pnpm', @dir).trusted_names
      write('pnpm-workspace.yaml', "base: &b\n  dangerouslyAllowAllBuilds: true\n<<: [*b]\n")

      assert_equal :all, M.new('pnpm', @dir).trusted_names, 'through a root merge'
      # And from pnpm's global config.yaml, which pnpm 11 and 12 apply to every project (probed:
      # under $XDG_CONFIG_HOME/pnpm, else ~/Library/Preferences/pnpm on macOS), even when the
      # project's own file says otherwise.
      xdg = File.join(@dir, 'xdg')
      FileUtils.mkdir_p(File.join(xdg, 'pnpm'))
      File.write(File.join(xdg, 'pnpm/config.yaml'), "dangerouslyAllowAllBuilds: true\n")
      write('pnpm-workspace.yaml', "dangerouslyAllowAllBuilds: false\n")
      ENV['XDG_CONFIG_HOME'] = xdg

      assert_equal :all, M.new('pnpm', @dir).trusted_names, 'from the global config.yaml'
      ENV['pnpm_config_dangerously_allow_all_builds'] = 'true'

      assert_equal :all, M.new('pnpm', @dir).trusted_names
      ENV.delete('pnpm_config_dangerously_allow_all_builds')
      ENV['PNPM_CONFIG_DANGEROUSLY_ALLOW_ALL_BUILDS'] = 'true'

      assert_equal :all, M.new('pnpm', @dir).trusted_names
      manifests = { 'hue' => { 'dependencies' => { 'left-pad' => 'github:evil/left-pad' } } }

      assert_equal ['hue: left-pad (github:evil/left-pad)'],
                   Proscenium::CLI::Rules.trusted_substitutions(:all, manifests)
    ensure
      ENV.delete('pnpm_config_dangerously_allow_all_builds')
      ENV.delete('PNPM_CONFIG_DANGEROUSLY_ALLOW_ALL_BUILDS')
      xdg_was ? ENV['XDG_CONFIG_HOME'] = xdg_was : ENV.delete('XDG_CONFIG_HOME')
    end

    # An empty list would switch the check off, so a Bun that cannot print one is refused.
    it "refuses when Bun's default list cannot be read" do
      skip 'the fake manager is a shell script' if Gem.win_platform?

      write('package.json', '{}')
      write('bin/bun', "#!/bin/sh\n[ \"$1\" = --version ] && echo 1.4.2 && exit 0\n" \
                       "exit $FAKE_EXIT\n")
      File.chmod(0o755, File.join(@dir, 'bin/bun'))
      path = ENV.fetch('PATH', nil)
      begin
        ENV['PATH'] = File.join(@dir, 'bin')
        manager = M.new('bun', @dir).check_version!
        { '1' => 'a failing Bun', '0' => 'an empty list' }.each do |exit_status, label|
          ENV['FAKE_EXIT'] = exit_status

          assert_equal('PSM-E-BUN-DEFAULT-TRUSTED', code { manager.trusted_names }, label)
        end
      ensure
        ENV['PATH'] = path
        ENV.delete('FAKE_EXIT')
      end
    end

    it 'ignores a linker outside the [install] table' do
      write('bunfig.toml', "linker = \"hoisted\"\n[test]\nlinker = \"hoisted\"\n")

      assert_nil bun.bun_linker
    end
  end

  # Windows editors and PowerShell write one; Node, pnpm and Bun all accept it.
  it 'reads a package.json with a byte order mark' do
    write('package.json',
          "\uFEFF{\"packageManager\": \"pnpm@12.9.1\", \"trustedDependencies\": []}")

    assert_equal 'pnpm', M.select(@dir).name
    write('bunfig.toml', "[install]\nlinker = \"isolated\"\n")

    assert_same M, M.new('bun', @dir).check_project!(frozen: true).class
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

  # Bun installs an app its ancestor's workspace patterns do not match as a project of its own
  # (probed on Bun 1.4.2), so only a matching pattern makes it nested.
  it 'accepts an app an ancestor package.json workspace does not include' do
    app = File.join(@dir, 'services', 'app')
    FileUtils.mkdir_p(app)
    write('package.json', '{"workspaces": ["frontend/*", "!services/app"]}')

    assert_same M, M.new('pnpm', app).check_project!.class
    write('package.json', '{"workspaces": {"packages": ["services/*"]}}')

    assert_equal('PSM-E-NESTED-WORKSPACE', code { M.new('pnpm', app).check_project! })
    # Bun reads full glob syntax, braces included.
    write('package.json', '{"workspaces": ["services/{app,other}"]}')

    assert_equal('PSM-E-NESTED-WORKSPACE', code { M.new('pnpm', app).check_project! })
    # Bun reads a trailing comma Ruby refuses; a workspace root it cannot be sure leaves the app out
    # counts as enclosing it, before anything is written.
    write('package.json', '{"workspaces": ["services/*",],}')

    assert_equal('PSM-E-NESTED-WORKSPACE', code { M.new('pnpm', app).check_project! })
    # Whatever JSON escapes spell the key, as Bun decodes them.
    write('package.json', '{"worksp\\u0061ces": ["services/*"],}')

    assert_equal('PSM-E-NESTED-WORKSPACE', code { M.new('pnpm', app).check_project! })
    write('package.json', '{"name": "tools",}')

    assert_same M, M.new('pnpm', app).check_project!.class
    # A `**/` matches no directory too, as Bun's glob does, wherever it sits.
    ['services/**/app', '**/services/app', '**/services/**/app'].each do |pattern|
      write('package.json', JSON.generate('workspaces' => [pattern]))

      assert_equal('PSM-E-NESTED-WORKSPACE', code { M.new('pnpm', app).check_project! }, pattern)
    end
  end
end
