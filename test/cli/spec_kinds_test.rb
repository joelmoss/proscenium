# frozen_string_literal: true

require_relative 'helper'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../package_manager/stage_a/bundle'

# C10 (#154): every kind of dependency spec a gem may declare (a range, a prerelease, a dist-tag,
# an npm: alias, a GitHub reference and a tarball URL) installs from the gem's context exactly as
# from a native workspace package declaring the same, in the same install. "Exactly" means the
# context and the native package reach the one same directory for each dependency.
#
# Runs only with STAGE_A=1: it needs pnpm, Bun and the network.
describe 'dependency spec kinds' do
  LIB = File.expand_path('../../lib', __dir__)
  EXE = File.expand_path('../../exe/proscenium', __dir__)
  GEM = 'stage_a_specs'
  SOURCE = File.join(StageA::Bundle::GEMS, GEM)
  MANIFEST = JSON.parse(File.read(File.join(SOURCE, 'package.json')))
  # The range, the prerelease and the alias, as resolved: ms 2.1.3 is the newest 2.x.
  VERSIONS = { 'ms' => '2.1.3', 'ms-beta' => '3.0.0-beta.2', 'ms-old' => '2.0.0' }.freeze

  before do
    skip 'set STAGE_A=1 to run (needs pnpm, Bun and the network)' unless ENV['STAGE_A']
    @dir = Dir.mktmpdir('spec_kinds')
  end

  after do
    StageA::Bundle.writable!(@dir) if @dir
    FileUtils.rm_rf(@dir) if @dir
  end

  # An app bundling only the fixture gem, installed as an archive, with a native workspace package
  # `packages/native` declaring the same dependencies. `source` is the gem's source directory.
  def app(manager, source = SOURCE)
    app = File.join(@dir, 'app')
    cache = File.join(app, 'vendor', 'cache')
    FileUtils.mkdir_p(cache)
    StageA::Bundle.build(source, cache)
    name = File.basename(source)
    File.write(File.join(app, 'Gemfile'), "source 'https://rubygems.org'\ngem '#{name}'\n")
    StageA::Bundle.bundle(app, @dir, 'install', '--local')

    manifest = JSON.parse(File.read(File.join(source, 'package.json')))
    native = File.join(app, 'packages', 'native')
    FileUtils.mkdir_p(native)
    declared = manifest.slice('dependencies', 'optionalDependencies')
    File.write(File.join(native, 'package.json'),
               JSON.generate({ 'name' => 'native', 'private' => true }.merge(declared)))
    package = { 'name' => 'app', 'private' => true }
    if manager == 'bun'
      package['workspaces'] = ['packages/*']
      package['trustedDependencies'] = []
      File.write(File.join(app, 'bunfig.toml'), "[install]\nlinker = \"isolated\"\n")
    else
      line = Proscenium::CLI::Manager::CAPABILITIES.dig('managers', 'pnpm', 'lines', 0, 'ci')
      package['packageManager'] = "pnpm@#{line}"
      File.write(File.join(app, 'pnpm-workspace.yaml'), "packages:\n  - packages/*\n")
    end
    File.write(File.join(app, 'package.json'), JSON.pretty_generate(package))
    app
  end

  def darwin? = RbConfig::CONFIG['host_os'].include?('darwin')

  def version(context, name)
    JSON.parse(File.read(File.join(context, 'node_modules', name, 'package.json')))['version']
  end

  def install(app, manager)
    Bundler.with_unbundled_env do
      Open3.capture3(StageA::Bundle.env(@dir), RbConfig.ruby, '-I', LIB, EXE, 'install',
                     '--manager', manager, chdir: app)
    end
  end

  # A gem source written for one case: `manifest` is its package.json.
  def gem_source(name, manifest)
    source = File.join(@dir, 'sources', name)
    FileUtils.mkdir_p(source)
    File.write(File.join(source, "#{name}.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = '#{name}'
        spec.version = '1.0.0'
        spec.summary = 'C14 fixture'
        spec.authors = ['Joel Moss']
        spec.files = %w[package.json]
        spec.metadata['proscenium.dependencies'] = 'true'
      end
    RUBY
    File.write(File.join(source, 'package.json'), JSON.generate(manifest))
    source
  end

  # A tarball the registry answers 404 for, so fetching it fails at once: a network error would
  # be retried for over a minute.
  UNFETCHABLE = 'https://registry.npmjs.org/left-pad/-/left-pad-0.0.0-absent.tgz'

  %w[pnpm bun].each do |manager|
    # C14: an optional dependency that cannot be fetched is left out, natively and from the
    # context alike, and the same dependency, required, still fails the install, naming the gem.
    it "skips an unfetchable optional dependency and fails on a required one, on #{manager}" do
      app = app(manager, gem_source('stage_d_optional', 'optionalDependencies' =>
                                                        { 'left-pad' => UNFETCHABLE }))
      _, err, status = install(app, manager)

      assert_predicate status, :success?, err
      refute_path_exists File.join(app,
                                   '.proscenium/packages/stage_d_optional/node_modules/left-pad')

      FileUtils.rm_rf(Dir.children(@dir).map { File.join(@dir, it) })
      app = app(manager, gem_source('stage_d_required', 'dependencies' =>
                                                        { 'left-pad' => UNFETCHABLE }))
      _, err, status = install(app, manager)

      assert_equal 6, status.exitstatus, err
      assert_includes err, 'PSM-E-NATIVE'
    end

    it "installs each spec kind from the context as natively, on #{manager}" do
      app = app(manager)
      _, err, status = install(app, manager)

      assert_predicate status, :success?, err

      context = File.join(app, '.proscenium', 'packages', GEM)
      native = File.join(app, 'packages', 'native')
      MANIFEST['dependencies'].each_key do |name|
        from_context = File.realpath(File.join(context, 'node_modules', name))
        from_native = File.realpath(File.join(native, 'node_modules', name))

        assert_equal from_native, from_context, "#{name} differs between the context and native"
      end

      assert_equal(VERSIONS.values, VERSIONS.keys.map { version(context, it) })

      # C15: fsevents runs only on macOS. Each host installs the variant it can run, and omits
      # an optional one it cannot, the same for the context as natively.
      fsevents = ->(dir) { File.exist?(File.join(dir, 'node_modules/fsevents/package.json')) }
      installed = { 'context' => fsevents.call(context), 'native' => fsevents.call(native) }

      assert_equal({ 'context' => darwin?, 'native' => darwin? }, installed)
      refute JSON.parse(File.read(File.join(context, 'package.json'))).key?('version'),
             "the gem's manifest version is not the context's: Ruby and JS versions are independent"
    end
  end
end
