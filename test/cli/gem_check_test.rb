# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

# `proscenium gem check`, against the Stage A fixture gems and small gems written per case.
describe Proscenium::CLI::GemCheck do
  include CLIHelper

  FIXTURES = File.expand_path('../package_manager/stage_a/gems', __dir__)

  # A gem source directory with this gemspec body and package.json, and any other files.
  OPTED_IN = { 'proscenium.dependencies' => 'true' }.freeze

  # Options: name, files (spec.files), metadata, deps (runtime dependencies), extra ({ path =>
  # body } written beside the manifest).
  def gem_dir(manifest: nil, **opts)
    name = opts.fetch(:name, 'example')
    files = opts.fetch(:files, %w[package.json index.js])
    metadata = opts.fetch(:metadata, OPTED_IN)
    deps = opts.fetch(:deps, [])
    dir = Dir.mktmpdir('gem_check')
    (@dirs ||= []) << dir
    File.write(File.join(dir, 'example.gemspec'), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = '#{name}'
        spec.version = '1.0.0'
        spec.summary = 'example'
        spec.authors = ['x']
        spec.files = #{files.inspect}
        spec.metadata = #{metadata.inspect}
        #{deps.map { "spec.add_dependency '#{it}'" }.join("\n  ")}
      end
    RUBY
    File.write(File.join(dir, 'package.json'), JSON.generate(manifest)) if manifest
    File.write(File.join(dir, 'index.js'), '')
    opts.fetch(:extra, {}).each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), body)
    end
    dir
  end

  after { @dirs&.each { FileUtils.rm_rf(it) } }

  def events(dir)
    status, out, = cli('gem', 'check', dir, '--json')
    [status, out.lines.map { JSON.parse(it) }]
  end

  def codes(dir)
    status, events = events(dir)
    [status, events.filter_map { it['code'] }]
  end

  it 'passes a widget fixture' do
    status, out, = cli('gem', 'check', File.join(FIXTURES, 'stage_a_widget_a'))

    assert_equal 0, status
    assert_includes out, 'stage_a_widget_a 1.0.0 passes every check'
  end

  it "flags hue's shape: the manifest left out of spec.files and React as a dependency" do
    assert_equal [2, %w[PSM-E-REACT PSM-E-GEM-FILES]],
                 codes(File.join(FIXTURES, 'stage_a_hue_shape'))
  end

  it 'flags a gem that has not opted in' do
    assert_equal [2, %w[PSM-E-NOT-OPTED-IN]], codes(File.join(FIXTURES, 'stage_a_assets'))
  end

  it 'flags a missing and an invalid manifest' do
    assert_equal [2, %w[PSM-E-MANIFEST]], codes(gem_dir)
    dir = gem_dir(manifest: {})
    File.write(File.join(dir, 'package.json'), '{nope')

    assert_equal [2, %w[PSM-E-MANIFEST]], codes(dir)
  end

  it 'flags install hooks and binding.gyp' do
    dir = gem_dir(manifest: { 'scripts' => { 'postinstall' => 'x', 'build' => 'y' } },
                  extra: { 'binding.gyp' => '{}' })

    status, events = events(dir)

    assert_equal [2, %w[PSM-E-HOOK]], [status, events.map { it['code'] }]
    assert_includes events.first['message'], '(postinstall, binding.gyp)'
  end

  it 'refuses dependency specs off the allow-list, and an alias to a gem context' do
    manifest = { 'dependencies' => {
      'ok-range' => '^1.2.3', 'ok-tag' => 'latest', 'ok-alias' => 'npm:other@^1',
      'ok-github' => 'github:owner/repo#abc123', 'ok-git' => 'git+https://host/x.git#v1',
      'ok-tarball' => 'https://host/x.tgz', 'bad-file' => 'file:../x', 'bad-link' => 'link:../x',
      'bad-workspace' => 'workspace:*', 'bad-catalog' => 'catalog:', 'bad-http' => 'http://host/x.tgz',
      'bad-alias' => 'npm:@rubygems/other@*',
      # Specs a manager reads as a local path or a Git repository, though they name no protocol.
      'bad-relative' => '../outside', 'bad-dot' => './x', 'bad-absolute' => '/outside',
      'bad-home' => '~/x', 'bad-spaced' => ' file:../x', 'bad-shorthand' => 'owner/repo',
      'ok-hyphen' => '1.2.3 - 2.3.4', 'ok-or' => '>=1.0.0 <2 || 3.x', 'ok-pre' => '3.0.0-beta.2',
      'ok-any' => '*', 'ok-empty' => '', 'ok-v' => 'v1.2.3', 'ok-query' => 'https://host/x.tgz?v=1',
      # An alias names a registry package, at a range or tag; its target is checked like any spec.
      'ok-alias-scoped' => 'npm:@scope/other@latest', 'ok-alias-bare' => 'npm:other',
      'bad-alias-link' => 'npm:other@link:../x', 'bad-alias-path' => 'npm:other@../x',
      'bad-alias-scoped' => 'npm:@scope/other@../x', 'bad-alias-name' => 'npm:file:../x',
      'bad-alias-url' => 'npm:https://host/x.tgz', 'bad-alias-empty' => 'npm:',
      'bad-alias-dots' => 'npm:other@..', 'bad-dots' => '..', 'bad-dot-only' => '.'
    } }

    status, events = events(gem_dir(manifest:))
    refused = events.map { it['message'][/(?:depends on|aliases) (\S+)/, 1] }

    assert_equal 2, status
    assert_equal %w[PSM-E-ALIAS PSM-E-SPEC], events.map { it['code'] }.uniq.sort
    assert_equal %w[bad-absolute bad-alias bad-alias-dots bad-alias-empty bad-alias-link
                    bad-alias-name bad-alias-path bad-alias-scoped bad-alias-url bad-catalog
                    bad-dot bad-dot-only bad-dots bad-file bad-home bad-http bad-link
                    bad-relative bad-shorthand bad-spaced bad-workspace],
                 refused.sort
  end

  # An optional dependency is installed for the gem too, so React there is its own copy as well.
  it 'flags React declared as an optional dependency' do
    manifest = { 'optionalDependencies' => { 'react' => '^18' } }
    problems = Proscenium::CLI::Rules.check('widget', manifest)

    assert_includes problems, ['PSM-E-REACT', { gem: 'widget', packages: 'react' }]
  end

  it 'flags React installed under an alias' do
    manifest = { 'dependencies' => { 'react18' => 'npm:react@18', 'dom' => 'npm:react-dom' } }
    problems = Proscenium::CLI::Rules.check('widget', manifest)

    assert_includes problems, ['PSM-E-REACT', { gem: 'widget', packages: 'react and react-dom' }]
  end

  # Windows drops a trailing dot from a path, so `foo.` would write foo's context there.
  it 'refuses a gem name ending in a dot' do
    refute Proscenium::CLI::Rules.valid_name?('foo.')
    assert Proscenium::CLI::Rules.valid_name?('foo.bar')
  end

  # A manifest field of the wrong type is a named problem, never a crash: the engine reads every
  # participating gem's manifest at boot.
  it 'refuses a manifest whose fields have the wrong type, by name' do
    {
      { 'dependencies' => 'x' } => 'dependencies is not an object',
      { 'dependencies' => { 'a' => { 'x' => 1 } } } => 'dependencies.a is not a string',
      { 'scripts' => [] } => 'scripts is not an object',
      { 'peerDependenciesMeta' => 'x' } => 'peerDependenciesMeta is not an object'
    }.each do |manifest, cause|
      status, events = events(gem_dir(manifest:))

      assert_equal [2, %w[PSM-E-MANIFEST]], [status, events.filter_map { it['code'] }], cause
      assert_includes events.first['message'], cause
    end
  end

  it 'flags workspaces and an unbacked gem reference, and accepts a backed one' do
    dir = gem_dir(manifest: { 'workspaces' => ['x'],
                              'dependencies' => { '@rubygems/other' => '*' } })

    assert_equal [2, %w[PSM-E-WORKSPACES PSM-E-CROSS-GEM]], codes(dir)
    backed = gem_dir(manifest: { 'dependencies' => { '@rubygems/other' => '*' } }, deps: %w[other])

    assert_equal [0, []], codes(backed)
  end

  # C27: the same verdict on every host for a name one host could not hold.
  %w[Example con nul.js com1 lpt9].push('x' * 205).each do |name|
    it "flags a gem named #{name[0, 12]}, which cannot be a JavaScript package everywhere" do
      assert_equal [2, %w[PSM-E-NAME]], codes(gem_dir(manifest: {}, name:))
    end
  end

  # Windows reserves COM1-COM9 and LPT1-LPT9, not COM0 or LPT0.
  it 'accepts a name a reserved one is only part of, and one at the length limit' do
    %w[console nul_gem com0 lpt0].push('x' * 204).each do |name|
      assert_equal [0, []], codes(gem_dir(manifest: {}, name:)), name
    end
  end

  # Bun trusts a dependency by name whatever its source: probed on Bun 1.4.2, a Git dependency's
  # postinstall ran under the name the app trusts, through a workspace context too.
  it 'finds a trusted name a gem reaches through Git, a URL or an alias to another package' do
    manifests = {
      'hue' => { 'dependencies' => { 'esbuild' => 'github:evil/esbuild', 'sharp' => 'npm:evil@1',
                                     'ms' => 'github:vercel/ms' },
                 'optionalDependencies' => { 'canvas' => 'https://evil.example/c.tgz' } },
      'ui' => { 'dependencies' => { 'esbuild' => '^0.25', 'sharp' => 'npm:sharp@0.33' } }
    }
    found = Proscenium::CLI::Rules.trusted_substitutions(%w[esbuild sharp canvas], manifests)

    assert_equal ['hue: esbuild (github:evil/esbuild)', 'hue: sharp (npm:evil@1)',
                  'hue: canvas (https://evil.example/c.tgz)'], found
  end

  # Install refuses it before any write, for Bun and for pnpm's build approvals alike.
  it 'is refused by an install for any manager that trusts the name' do
    context = Struct.new(:json).new(JSON.generate('dependencies' => { 'esbuild' => 'github:e/v' }))
    install = Proscenium::CLI::Install.new(Dir.pwd, nil)
    install.instance_variable_set(:@contexts, Struct.new(:contexts).new({ 'hue' => context }))
    manager = Struct.new(:name, :trusted_names)
    install.instance_variable_set(:@manager, manager.new('bun', %w[esbuild]))
    error = assert_raises(Proscenium::CLI::Error) { install.send(:check_trusted_sources) }

    assert_equal 'PSM-E-TRUSTED-SOURCE', error.code
    install.instance_variable_set(:@manager, manager.new('pnpm', %w[esbuild]))
    error = assert_raises(Proscenium::CLI::Error) { install.send(:check_trusted_sources) }

    assert_equal 'PSM-E-TRUSTED-SOURCE', error.code
    install.instance_variable_set(:@manager, manager.new('pnpm', []))

    assert_nil install.send(:check_trusted_sources)
    # Bun's trust is not even read when no gem reaches a package another way.
    context.json = JSON.generate('dependencies' => { 'esbuild' => '^0.25' })
    unread = Object.new
    def unread.name = 'bun'
    def unread.trusted_names = raise('read')
    install.instance_variable_set(:@manager, unread)

    assert_nil install.send(:check_trusted_sources)
  end

  it 'flags frontend files missing from spec.files, but not tests' do
    dir = gem_dir(manifest: {}, files: %w[package.json index.js lib/x.rb],
                  extra: { 'lib/x.rb' => '', 'lib/x.js' => '', 'lib/x.test.js' => '',
                           'test/y.js' => '' })

    status, events = events(dir)

    assert_equal [2, %w[PSM-E-GEM-FILES]], [status, events.map { it['code'] }]
    assert_includes events.first['message'], 'lib/x.js'
    refute_includes events.first['message'], 'test'
  end

  # A demo app beside the gem's code, which the gem ships nothing from, and tool configuration at
  # the root (proscenium-ui's).
  it 'leaves out a top-level directory the gem ships nothing from, and root tool config' do
    dir = gem_dir(manifest: {}, extra: { 'app/views/layouts/application.js' => '',
                                         'eslint.config.js' => '' })

    assert_equal [0, []], codes(dir)
  end

  it 'checks a built .gem from its archive' do
    source = File.join(FIXTURES, 'stage_a_widget_a')
    Dir.mktmpdir do |dir|
      spec = Dir.chdir(source) { Gem::Specification.load('stage_a_widget_a.gemspec') }
      file = Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
        Dir.chdir(source) { Gem::Package.build(spec) }
      end
      FileUtils.mv(File.join(source, file), dir)

      status, out, = cli('gem', 'check', File.join(dir, file))

      assert_equal 0, status, out
    end
  end

  it 'refuses a frontend root outside the gem' do
    outside = OPTED_IN.merge('proscenium.frontend_root' => '../outside')
    dir = gem_dir(manifest: {}, metadata: outside)

    assert_equal [2, %w[PSM-E-FRONTEND-ROOT]], codes(dir)
  end

  # A built gem has no directory to look in, but ships exactly its spec.files.
  it 'flags binding.gyp in a built .gem' do
    dir = gem_dir(manifest: {}, files: %w[package.json index.js binding.gyp],
                  extra: { 'binding.gyp' => '{}' })
    spec = Dir.chdir(dir) { Gem::Specification.load(File.join(dir, 'example.gemspec')) }
    file = Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
      Dir.chdir(dir) { Gem::Package.build(spec) }
    end
    status, = cli('gem', 'check', File.join(dir, file))
    _, events = events(File.join(dir, file))

    assert_equal [2, %w[PSM-E-HOOK]], [status, events.filter_map { it['code'] }]
  end

  # C31: a gem never ships a credential, which its context would commit; a Git user is not one.
  it 'refuses a dependency URL with a password in it' do
    dir = gem_dir(manifest: { 'dependencies' => {
                    # Joined, so the credential scanner on push does not read a fake as real.
                    'secret' => ['https://', 'user:fake', '@registry.example.com/s-1.0.0.tgz'].join,
                    'token' => ['git+https://', 'ghp_fake', '@github.com/o/r.git'].join,
                    'query' => ['https://registry.example.com/t.tgz?', 'token=fake'].join,
                    'git-user' => 'git+ssh://git@github.com/owner/repo.git#abc123',
                    'ssh' => ['git+ssh://', 'git:fake', '@github.com/o/r.git#abc123'].join,
                    'alias' => ['npm:other@https://', 'user:fake', '@host/x.tgz'].join,
                    # A server decodes the name, so `%74oken` is `token`.
                    'encoded' => ['https://registry.example.com/t.tgz?', '%74oken=fake'].join
                  } })
    status, events = events(dir)

    assert_equal [2, %w[PSM-E-CREDENTIAL] * 6], [status, events.map { it['code'] }]
  end

  # Minimal Docker and CI images run with LANG=C, where Ruby reads files as US-ASCII; package.json
  # is UTF-8 whatever the locale.
  it 'reads a package.json with non-ASCII text under the C locale' do
    dir = gem_dir(manifest: { 'description' => "Jos\u00e9's widget" })
    exe = File.expand_path('../../exe/proscenium', __dir__)
    out, status = Open3.capture2e({ 'LANG' => 'C', 'LC_ALL' => 'C' }, RbConfig.ruby, '-w', '-I',
                                  File.expand_path('../../lib', __dir__), exe, 'gem', 'check', dir)

    assert_predicate status, :success?, out
    refute_includes out, 'Encoding.default_external', 'the setting is not worth a warning'
  end

  # C29: a package.json read safely or not at all.
  describe 'an unsafe manifest' do
    def manifest_message(target)
      _, events = events(target)
      events.find { it['code'] == 'PSM-E-MANIFEST' }&.fetch('message')
    end

    def link(target, path)
      File.symlink(target, path)
    rescue NotImplementedError, Errno::EPERM, Errno::EACCES
      skip 'symlinks need privileges here'
    end

    it 'refuses one that links outside the gem' do
      dir = gem_dir
      outside = File.join(Dir.mktmpdir('outside').tap { @dirs << it }, 'package.json')
      File.write(outside, '{}')
      link(outside, File.join(dir, 'package.json'))

      assert_includes manifest_message(dir), 'it links outside the gem'
    end

    it 'refuses a FIFO without blocking on it' do
      skip 'no FIFOs on Windows' if Gem.win_platform?
      dir = gem_dir
      File.mkfifo(File.join(dir, 'package.json'))

      assert_includes manifest_message(dir), 'it is not a regular file'
    end

    it 'refuses one larger than 1 MB' do
      dir = gem_dir(manifest: { 'description' => 'x' * (1024 * 1024) })

      assert_includes manifest_message(dir), 'it is larger than 1 MB'
    end

    it 'refuses a built gem whose package.json is a link entry' do
      dir = gem_dir(files: %w[package.json index.js])
      File.write(File.join(dir, 'real.json'), '{}')
      link('real.json', File.join(dir, 'package.json'))
      spec = Dir.chdir(dir) { Gem::Specification.load(File.join(dir, 'example.gemspec')) }
      file = Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
        Dir.chdir(dir) { Gem::Package.build(spec) }
      end

      assert_includes manifest_message(File.join(dir, file)), 'it is not a regular file'
    end
  end

  it 'needs exactly one gemspec' do
    Dir.mktmpdir do |dir|
      status, _, err = cli('gem', 'check', dir)

      assert_equal 2, status
      assert_includes err, 'PSM-E-GEMSPEC'
    end
  end
end
