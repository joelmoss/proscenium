# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'bundle'
require_relative 'context'

# The CI half of the Stage A london leg (#154): stage_a_hue_shape, which has hue's manifest shape,
# installed by Bundler into a read-only bundle with no node_modules of its own, gets its
# dependencies from a hand-written context through pnpm, and the seam routes its imports there.
#
# Runs only with STAGE_A=1, because it needs pnpm and the network (npm and GitHub; the hermetic
# registry is not built yet). The stage-a CI job sets it.
class StageA::HueShapeTest < ActiveSupport::TestCase
  GEM = StageA::Bundle::GIT
  ENTRY = "node_modules/@rubygems/#{GEM}/index.js".freeze
  DIR = Dir.mktmpdir('stage_a_hue_shape')
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
        'name' => 'stage-a-app', 'private' => true
      )}\n")
      StageA::Context.register_pnpm(app)
      context = StageA::Context.write(app, GEM, roots.fetch(GEM))
      pnpm(app, 'install')

      { app: File.realpath(app), roots:, context: File.realpath(context) }
    end
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
    overrides[:StageAContexts] = { GEM => context } if seam
    Proscenium::Builder.build_to_string(ENTRY, root: app, **overrides)[:response]
  end

  # The package directories a bundled build includes, from esbuild's `// path` comments.
  def bundled_packages(code)
    code.scan(%r{^// node_modules/\.pnpm/([^/]+)/node_modules/}).flatten.uniq.sort
  end

  it 'installs from a gem root with no node_modules of its own' do
    root = self.class.setup_app[:roots].fetch(GEM)

    refute_path_exists File.join(root, 'node_modules')
    refute File.writable?(root)
  end

  it 'installs the context as a workspace, without a version and from no registry (C42)' do
    lock = File.read(File.join(app, 'pnpm-lock.yaml'))

    assert_includes lock, "  .proscenium/packages/#{GEM}:"
    refute_includes lock, "@rubygems/#{GEM}@"
    refute JSON.parse(File.read(File.join(context, 'package.json'))).key?('version')
  end

  it 'puts react and react-dom, declared as plain dependencies, in the context (C43)' do
    %w[react react-dom escape-string-regexp].each do |name|
      link = File.join(context, 'node_modules', name)

      assert File.symlink?(link), "#{name} is not linked into the context"
      assert_includes File.realpath(link), '/node_modules/.pnpm/'
    end
  end

  it 'leaves every committed input byte-identical across frozen installs (C08)' do
    files = %w[package.json pnpm-lock.yaml pnpm-workspace.yaml].map { File.join(app, it) } +
            [File.join(context, 'package.json')]
    before = files.map { File.binread(it) }
    2.times { self.class.pnpm(app, 'install', '--frozen-lockfile') }

    assert_equal(before, files.map { File.binread(it) })
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

  # The positive controls: without the seam the context is out of reach, so the same entry
  # resolves none of its dependencies.
  it 'reaches none of them without the seam' do
    assert_empty bundled_packages(build(seam: false, bundle: true))
    assert_match(/from "react"/, build(seam: false, bundle: false))
  end
end
