# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'

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
    assert_includes out, 'stage_a_widget_a 1.0.0 meets the Proscenium gem contract.'
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
      'bad-alias' => 'npm:@rubygems/other@*'
    } }

    status, events = events(gem_dir(manifest:))
    refused = events.map { it['message'][/(?:depends on|aliases) (\S+)/, 1] }

    assert_equal 2, status
    assert_equal %w[PSM-E-ALIAS PSM-E-SPEC], events.map { it['code'] }.uniq.sort
    assert_equal %w[bad-alias bad-catalog bad-file bad-http bad-link bad-workspace], refused.sort
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

  it 'accepts a name a reserved one is only part of, and one at the length limit' do
    %w[console nul_gem].push('x' * 204).each do |name|
      assert_equal [0, []], codes(gem_dir(manifest: {}, name:)), name
    end
  end

  it 'flags frontend files missing from spec.files, but not tests' do
    dir = gem_dir(manifest: {},
                  extra: { 'lib/x.js' => '', 'lib/x.test.js' => '',
                           'test/y.js' => '' })

    status, events = events(dir)

    assert_equal [2, %w[PSM-E-GEM-FILES]], [status, events.map { it['code'] }]
    assert_includes events.first['message'], 'lib/x.js'
    refute_includes events.first['message'], 'test'
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
