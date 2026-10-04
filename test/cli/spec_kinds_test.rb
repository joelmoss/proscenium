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
  # `packages/native` declaring the same dependencies.
  def app(manager)
    app = File.join(@dir, 'app')
    cache = File.join(app, 'vendor', 'cache')
    FileUtils.mkdir_p(cache)
    StageA::Bundle.build(SOURCE, cache)
    File.write(File.join(app, 'Gemfile'), "source 'https://rubygems.org'\ngem '#{GEM}'\n")
    StageA::Bundle.bundle(app, @dir, 'install', '--local')

    native = File.join(app, 'packages', 'native')
    FileUtils.mkdir_p(native)
    File.write(File.join(native, 'package.json'),
               JSON.generate('name' => 'native', 'private' => true,
                             'dependencies' => MANIFEST['dependencies']))
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

  def version(context, name)
    JSON.parse(File.read(File.join(context, 'node_modules', name, 'package.json')))['version']
  end

  def install(app, manager)
    Bundler.with_unbundled_env do
      Open3.capture3(StageA::Bundle.env(@dir), RbConfig.ruby, '-I', LIB, EXE, 'install',
                     '--manager', manager, chdir: app)
    end
  end

  %w[pnpm bun].each do |manager|
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
      refute JSON.parse(File.read(File.join(context, 'package.json'))).key?('version'),
             "the gem's manifest version is not the context's: Ruby and JS versions are independent"
    end
  end
end
