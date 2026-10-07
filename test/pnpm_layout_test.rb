# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'open3'
require 'tmpdir'
require 'proscenium/dependency_context'
require_relative 'package_manager/stage_a/bundle'

# What the engine builds from a real pnpm install of a gem with ui-gem's manifest shape (#154):
# stage_a_hue_shape, installed by Bundler into a read-only bundle with no node_modules of its own,
# gets its dependencies from its context through pnpm, and the engine routes its imports there. The
# pnpm counterpart of bun_layout_test.rb, and the only build against a real pnpm tree on every
# supported pnpm line: the package-manager job's pnpm 12 leg and the nightly canary run it, so a
# pnpm release that lays files out where the engine cannot reach them fails here.
#
# Runs only with STAGE_A=1, because it needs pnpm and the network. The package-manager CI job sets
# it.
class Proscenium::PnpmLayoutTest < ActiveSupport::TestCase
  GEM = StageA::Bundle::GIT
  ENTRY = "node_modules/@rubygems/#{GEM}/index.js".freeze
  DIR = Dir.mktmpdir('pnpm_layout')
  Minitest.after_run do
    StageA::Bundle.writable!(DIR)
    FileUtils.rm_rf(DIR)
  end

  # Installs once for the whole class: the bundle, then the app with its context.
  def self.setup_app
    @setup_app ||= begin
      roots = StageA::Bundle.install(DIR).transform_values { File.realpath(it) }
      app = File.join(DIR, 'app')
      File.write(File.join(app, 'package.json'), "#{JSON.pretty_generate(
        'name' => 'pnpm-layout-app', 'private' => true
      )}\n")
      File.write(File.join(app, 'pnpm-workspace.yaml'), "packages:\n  - .proscenium/packages/*\n")
      context = write_context(app, roots.fetch(GEM))
      pnpm(app, 'install')

      { app: File.realpath(app), roots:, context: File.realpath(context) }
    end
  end

  # The gem's context, from its installed package.json through the shipped projection.
  def self.write_context(app, root)
    manifest = JSON.parse(File.read(File.join(root, 'package.json')))
    dir = File.join(app, '.proscenium/packages', GEM)
    FileUtils.mkdir_p(dir)
    context = Proscenium::DependencyContext.project(GEM, manifest)
    File.write(File.join(dir, 'package.json'), Proscenium::DependencyContext.to_json(context))
    dir
  end

  def self.pnpm(app, *args)
    out, status = Open3.capture2e('pnpm', *args, chdir: app)
    raise "pnpm #{args.join(' ')} failed:\n#{out}" unless status.success?

    out
  end

  before { skip 'set STAGE_A=1 to run (needs pnpm and the network)' unless ENV['STAGE_A'] }

  def app = self.class.setup_app[:app]
  def context = self.class.setup_app[:context]

  def build(seam:, bundle:)
    overrides = { RubyGems: self.class.setup_app[:roots], Bundle: bundle, Aliases: {},
                  External: [], Precompile: [] }
    overrides[:DependencyContexts] = { GEM => context } if seam
    Proscenium::Builder.build_to_string(ENTRY, root: app, **overrides)[:response]
  end

  # The package directories a bundled build includes, from esbuild's `// path` comments.
  def bundled_packages(code)
    code.scan(%r{^// node_modules/\.pnpm/([^/]+)/node_modules/}).flatten.uniq.sort
  end

  # C28: the gems are installed read-only, as a shared or system install is, with no node_modules
  # of their own. The write is the control that read-only is real, not just a mode bit.
  it 'installs from read-only gem roots with no node_modules of their own' do
    roots = self.class.setup_app[:roots]
    file = File.join(roots.fetch('stage_a_widget_a'), 'index.js')

    refute_path_exists File.join(roots.fetch(GEM), 'node_modules')
    assert_raises(Errno::EACCES) { File.write(file, '//', mode: 'a') }
    next if Gem.win_platform? # A read-only directory still accepts new files on Windows.

    assert_raises(Errno::EACCES) { File.write(File.join(File.dirname(file), 'new.js'), '') }
  end

  it 'bundles the context dependencies, with one React' do
    packages = bundled_packages(build(seam: true, bundle: true))

    assert_equal 1, packages.grep(/\Areact@/).size, packages.inspect
    assert_equal 1, packages.grep(/\Areact-dom@/).size, packages.inspect
    assert_equal 1, packages.grep(/\Aescape-string-regexp@/).size, packages.inspect
  end

  it 'imports the context dependencies by their real paths when unbundling' do
    code = build(seam: true, bundle: false)

    assert_match %r{from "/node_modules/\.pnpm/react@[^/]+/node_modules/react/index\.js"}, code
    assert_match %r{from "/node_modules/\.pnpm/escape-string-regexp@[^"]+"}, code
    refute_includes code, "/node_modules/@rubygems/#{GEM}/node_modules/"
  end

  # The positive controls: without the context map the context is out of reach, so the same entry
  # resolves none of its dependencies.
  it 'reaches none of them without the context map' do
    assert_empty bundled_packages(build(seam: false, bundle: true))
    assert_match(/from "react"/, build(seam: false, bundle: false))
  end
end
