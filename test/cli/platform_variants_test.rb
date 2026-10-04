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
  def installed(manifest, metadata: OPT_IN)
    root = File.join(@dir, 'installed')
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'package.json'), JSON.generate(manifest))
    Installed.new('widget', Gem::Version.new('1.0.0'), 'widget-1.0.0-arm64-darwin', metadata, root)
  end

  # Builds another variant of the gem into the cache.
  def variant(platform, manifest, metadata: OPT_IN)
    source = File.join(@dir, "src-#{platform}")
    FileUtils.mkdir_p(source)
    File.write(File.join(source, 'package.json'), JSON.generate(manifest))
    spec = Gem::Specification.new do |s|
      s.name = 'widget'
      s.version = '1.0.0'
      s.summary = 'C33 fixture'
      s.authors = ['x']
      s.platform = platform
      s.files = %w[package.json]
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

  it 'finds a variant with other dependencies' do
    file = variant('x86_64-linux', { 'dependencies' => { 'ms' => '^2.0.0' } })

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
