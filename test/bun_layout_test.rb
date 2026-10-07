# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'package_manager/stage_a/bundle'

# What Bun does with registered contexts, built through the engine (#154): the only test that
# builds against a real Bun-installed tree, under both linkers. stage_a_widget_a needs ms 2.0.0 and
# stage_a_widget_b ms 2.1.3; the app declares ms 2.1.3 and React, which both widgets take as a
# peer. Contexts are written with the shipped projection, as `proscenium install` writes them.
#
# Runs only with STAGE_A=1: it needs Bun and the network. The package-manager CI job sets it.
class Proscenium::BunLayoutTest < ActiveSupport::TestCase
  WIDGETS = %w[stage_a_widget_a stage_a_widget_b].freeze
  DIR = Dir.mktmpdir('bun_layout')
  Minitest.after_run do
    StageA::Bundle.writable!(DIR)
    FileUtils.rm_rf(DIR)
  end

  def self.roots = @roots ||= StageA::Bundle.install(DIR).transform_values { File.realpath(it) }

  # An app per linker, registered as the plan requires: an explicit linker and an explicit, empty
  # trustedDependencies.
  def self.app(linker)
    (@apps ||= {})[linker] ||= begin
      dir = File.join(DIR, linker)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'package.json'), "#{JSON.pretty_generate(
        'name' => 'bun-layout-app', 'private' => true, 'workspaces' => ['.proscenium/packages/*'],
        'trustedDependencies' => [],
        'dependencies' => { 'ms' => '2.1.3', 'react' => '18.3.1', 'react-dom' => '18.3.1' }
      )}\n")
      File.write(File.join(dir, 'bunfig.toml'), "[install]\nlinker = \"#{linker}\"\n")
      WIDGETS.each { write_context(dir, it) }
      bun(dir, 'install')
      File.realpath(dir)
    end
  end

  # The gem's context, from its installed package.json through the shipped projection.
  def self.write_context(app, gem)
    manifest = JSON.parse(File.read(File.join(roots.fetch(gem), 'package.json')))
    path = File.join(app, '.proscenium/packages', gem, 'package.json')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, Proscenium::DependencyContext.to_json(
                       Proscenium::DependencyContext.project(gem, manifest)
                     ))
  end

  def self.bun(dir, *args)
    out, status = Open3.capture2e('bun', *args, chdir: dir)
    raise "bun #{args.join(' ')} failed:\n#{out}" unless status.success?

    out
  end

  before { skip 'set STAGE_A=1 to run (needs Bun and the network)' unless ENV['STAGE_A'] }

  def version(path) = JSON.parse(File.read(File.join(path, 'package.json')))['version']

  def build(linker, gem, bundle:)
    app = self.class.app(linker)
    contexts = WIDGETS.to_h { [it, File.join(app, '.proscenium/packages', it)] }
    overrides = { RubyGems: self.class.roots, Bundle: bundle, Aliases: {}, External: [],
                  Precompile: [], DependencyContexts: contexts }
    entry = "node_modules/@rubygems/#{gem}/index.js"
    Proscenium::Builder.build_to_string(entry, root: app, **overrides)[:response]
  end

  it 'nests a conflicting copy under the context with the hoisted linker' do
    app = self.class.app('hoisted')
    nested = File.join(app, '.proscenium/packages/stage_a_widget_a/node_modules/ms')

    assert_equal '2.0.0', version(nested)
    refute File.symlink?(nested)
    assert_equal '2.1.3', version(File.join(app, 'node_modules/ms'))
    refute_path_exists File.join(app, '.proscenium/packages/stage_a_widget_b/node_modules/ms')
  end

  it 'links every context dependency into the store with the isolated linker' do
    app = self.class.app('isolated')
    a = File.join(app, '.proscenium/packages/stage_a_widget_a/node_modules/ms')

    assert File.symlink?(a)
    assert_equal '2.0.0', version(a)
    b = File.join(app, '.proscenium/packages/stage_a_widget_b/node_modules/ms')

    assert_equal '2.1.3', version(b)
  end

  # The module paths esbuild names in a bundled build, for each widget under each linker.
  EXPECTED = {
    'hoisted' => {
      'stage_a_widget_a' => %w[.proscenium/packages/stage_a_widget_a/node_modules/ms/index.js
                               node_modules/react/index.js],
      'stage_a_widget_b' => %w[node_modules/ms/index.js node_modules/react/index.js]
    },
    'isolated' => {
      'stage_a_widget_a' => %w[node_modules/.bun/ms@2.0.0/node_modules/ms/index.js
                               node_modules/.bun/react@18.3.1/node_modules/react/index.js],
      'stage_a_widget_b' => %w[node_modules/.bun/ms@2.1.3/node_modules/ms/index.js
                               node_modules/.bun/react@18.3.1/node_modules/react/index.js]
    }
  }.freeze

  EXPECTED.each do |linker, widgets|
    it "bundles each widget's own ms and the app's one React (#{linker})" do
      widgets.each do |gem, expected|
        code = build(linker, gem, bundle: true)
        modules = code.scan(%r{^// (\S+/(?:ms|react)/index\.js)$}).flatten

        assert_equal expected.sort, modules.sort, gem
      end
    end
  end

  it 'imports the nested copy from under the context when unbundling (hoisted)' do
    code = build('hoisted', 'stage_a_widget_a', bundle: false)

    assert_includes code, '"/.proscenium/packages/stage_a_widget_a/node_modules/ms/index.js"'
  end

  # simple-git-hooks is on Bun's default trusted list, and its postinstall writes a Git hook.
  it "runs a gem-introduced package's script only without an explicit trustedDependencies" do
    results = { 'absent' => nil, 'empty' => [] }.to_h do |name, trusted|
      dir = File.join(DIR, "trust-#{name}")
      FileUtils.mkdir_p(File.join(dir, '.proscenium/packages/g'))
      system('git', 'init', '-q', dir, exception: true)
      app = { 'name' => 'app', 'private' => true, 'workspaces' => ['.proscenium/packages/*'],
              'simple-git-hooks' => { 'pre-commit' => 'true' } }
      app['trustedDependencies'] = trusted if trusted
      File.write(File.join(dir, 'package.json'), JSON.generate(app))
      File.write(File.join(dir, '.proscenium/packages/g/package.json'),
                 JSON.generate('name' => '@rubygems/g', 'private' => true,
                               'dependencies' => { 'simple-git-hooks' => '2.13.1' }))
      File.write(File.join(dir, 'bunfig.toml'), "[install]\nlinker = \"hoisted\"\n")
      out = self.class.bun(dir, 'install', '--verbose')
      [name, out.include?('Starting scripts for "simple-git-hooks"')]
    end

    assert_equal({ 'absent' => true, 'empty' => false }, results)
  end
end
