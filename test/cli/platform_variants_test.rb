# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'proscenium/cli/platform_variants'

# C33 (#154): a gem's platform variants must declare the same JavaScript dependencies and
# participation, because the lock holds one set. Other variants are read from the Bundler cache.
describe Proscenium::CLI::PlatformVariants do
  PV = Proscenium::CLI::PlatformVariants
  Installed = Struct.new(:name, :version, :full_name, :metadata, :full_gem_path)
  OPT_IN = { 'proscenium.dependencies' => 'true' }.freeze
  DEPS = { 'dependencies' => { 'ms' => '^2.1.3' } }.freeze

  before do
    @dir = Dir.mktmpdir('variants')
    @cache = File.join(@dir, 'vendor/cache')
    FileUtils.mkdir_p(@cache)
  end

  after { FileUtils.rm_rf(@dir) }

  # The variant installed here, arm64-darwin, with this package.json.
  def installed(manifest, metadata: OPT_IN, bom: false)
    root = File.join(@dir, 'installed')
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'package.json'), "#{"\uFEFF" if bom}#{JSON.generate(manifest)}")
    Installed.new('widget', Gem::Version.new('1.0.0'), 'widget-1.0.0-arm64-darwin', metadata, root)
  end

  # Builds another variant of the gem into the cache.
  def variant(platform, manifest, metadata: OPT_IN, gyp: false)
    source = File.join(@dir, "src-#{platform}")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, 'package.json'), JSON.generate(manifest))
    File.write(File.join(source, 'binding.gyp'), '{}') if gyp
    spec = Gem::Specification.new do |s|
      s.name = 'widget'
      s.version = '1.0.0'
      s.summary = 'C33 fixture'
      s.authors = ['x']
      s.platform = platform
      s.files = gyp ? %w[package.json binding.gyp] : %w[package.json]
      s.metadata = metadata
    end
    file = Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
      Dir.chdir(source) { Gem::Package.build(spec) }
    end
    FileUtils.mv(File.join(source, file), @cache)
    file
  end

  it 'passes variants with the same dependencies and participation' do
    variant('x86_64-linux', DEPS.merge('version' => '9.9.9', 'main' => 'linux.js'))

    assert_empty PV.differences(@cache, [installed(DEPS)])
  end

  # The app's package.json `proscenium` key decides participation, over the gemspec's opt-in.
  it "honours the app's participation overrides" do
    variant('x86_64-linux', { 'dependencies' => { 'ms' => '^3' } })

    assert_empty PV.differences(@cache, [installed(DEPS)], overrides: { 'widget' => false })

    FileUtils.rm_rf(Dir[File.join(@cache, '*')])
    variant('x86_64-linux', { 'dependencies' => { 'ms' => '^3' } }, metadata: {})

    refute_empty PV.differences(@cache, [installed(DEPS, metadata: {})],
                                overrides: { 'widget' => true })
  end

  # Windows editors and PowerShell write a byte order mark; it is not a dependency.
  it 'compares a manifest with a byte order mark by its dependencies' do
    variant('x86_64-linux', DEPS)

    assert_empty PV.differences(@cache, [installed(DEPS, bom: true)])
    other = { 'dependencies' => { 'ms' => '^3' } }

    refute_empty PV.differences(@cache, [installed(other, bom: true)])
  end

  it 'finds a variant with other dependencies' do
    file = variant('x86_64-linux', { 'dependencies' => { 'ms' => '^2.0.0' } })

    assert_equal [['widget', file]], PV.differences(@cache, [installed(DEPS)])
  end

  # The context drops scripts and workspaces, so only the author contract tells these variants
  # apart: the host that installs one would refuse it.
  it 'finds a variant its package.json rules refuse, with the same dependencies' do
    [[DEPS.merge('scripts' => { 'postinstall' => 'x' }), false],
     [DEPS.merge('workspaces' => ['a']), false], [DEPS, true]].each do |manifest, gyp|
      FileUtils.rm_rf(Dir[File.join(@cache, '*')])
      file = variant('x86_64-linux', manifest, gyp:)

      assert_equal [['widget', file]], PV.differences(@cache, [installed(DEPS)]), manifest
    end
  end

  # A gem's own React only warns at install, so it is no reason to call a variant different.
  it 'passes variants that warn alike about their own React' do
    react = DEPS.merge('dependencies' => { 'react' => '^18' })
    variant('x86_64-linux', react)

    assert_empty PV.differences(@cache, [installed(react)])
  end

  # Its root package.json matches, but a host that installs it refuses its frontend root.
  it 'finds a variant whose frontend root is outside the gem' do
    file = variant('x86_64-linux', DEPS,
                   metadata: OPT_IN.merge('proscenium.frontend_root' => '../x'))

    assert_equal [['widget', file]], PV.differences(@cache, [installed(DEPS)])
  end

  it 'finds a variant that does not participate' do
    file = variant('x86_64-linux', DEPS, metadata: {})

    assert_equal [['widget', file]], PV.differences(@cache, [installed(DEPS)])
  end

  it 'finds nothing without a cache, or for the installed variant itself' do
    variant('arm64-darwin', { 'dependencies' => { 'ms' => '^1.0.0' } })

    assert_empty PV.differences(@cache, [installed(DEPS)])
    assert_empty PV.differences(File.join(@dir, 'none'), [installed(DEPS)])
  end
end
