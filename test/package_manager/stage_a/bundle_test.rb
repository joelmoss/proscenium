# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'tmpdir'
require_relative 'bundle'

# The Stage A fixture gems, as Bundler installs them. Everything the pilot proves starts from
# these roots, so this pins what each one ships and that nothing can write into them.
class StageA::BundleTest < ActiveSupport::TestCase
  DIR = Dir.mktmpdir('stage_a')
  Minitest.after_run do
    StageA::Bundle.writable!(DIR)
    FileUtils.rm_rf(DIR)
  end

  # One install for the whole class: it builds and installs five gems.
  def self.roots = @roots ||= StageA::Bundle.install(DIR)

  def roots = self.class.roots

  # The archive's own specification. An installed one does not keep its file list.
  def spec(name)
    roots
    Gem::Package.new(Dir[File.join(DIR, 'app', 'vendor', 'cache', "#{name}-*.gem")].first).spec
  end

  def manifest(name)
    JSON.parse(File.read(File.join(roots.fetch(name), 'package.json')))
  end

  it 'installs every fixture gem' do
    assert_equal %w[gem_npm stage_a_assets stage_a_hue_shape stage_a_widget_a stage_a_widget_b],
                 roots.keys.sort
  end

  it 'installs each archive gem with exactly its listed files' do
    %w[gem_npm stage_a_assets stage_a_widget_a stage_a_widget_b].each do |name|
      assert_equal spec(name).files.sort, Dir.children(roots.fetch(name)).sort, name
    end
  end

  it 'opts in every gem that ships a package.json, and only those' do
    roots.each do |name, root|
      metadata = (name == 'stage_a_hue_shape' ? hue_shape_spec : spec(name)).metadata
      opt_in = metadata['proscenium.dependencies']

      if File.exist?(File.join(root, 'package.json'))
        assert_equal 'true', opt_in, name
      else
        assert_nil opt_in, name
      end
    end
  end

  it 'gives the widgets a React peer and conflicting ms versions' do
    a = manifest('stage_a_widget_a')
    b = manifest('stage_a_widget_b')

    assert_equal({ 'react' => '^18.3.1' }, a['peerDependencies'])
    assert_equal({ 'react' => '^18.3.1' }, b['peerDependencies'])
    assert_equal(['2.0.0', '2.1.3'], [a, b].map { it['dependencies']['ms'] })
  end

  it "installs stage_a_hue_shape from Git with hue's manifest shape" do
    root = roots.fetch('stage_a_hue_shape')
    pkg = manifest('stage_a_hue_shape')

    assert_includes root, '/bundler/gems/'
    refute_includes hue_shape_spec.files, 'package.json'
    refute pkg.key?('version')
    assert_equal %w[react react-dom], pkg['dependencies'].keys.grep(/\Areact/).sort
    assert(pkg['dependencies'].values.any? { it.start_with?('github:') })
  end

  it 'makes installed gem roots read-only' do
    file = File.join(roots.fetch('stage_a_widget_a'), 'index.js')

    assert_raises(Errno::EACCES) { File.write(file, '//', mode: 'a') }
    next if Gem.win_platform? # A read-only directory still accepts new files on Windows.

    assert_raises(Errno::EACCES) { File.write(File.join(File.dirname(file), 'new.js'), '') }
  end

  private

  # A Git gem's gemspec is read from its checkout; there is no installed specification.
  def hue_shape_spec
    root = roots.fetch(StageA::Bundle::GIT)
    Gem::Specification.load(File.join(root, "#{StageA::Bundle::GIT}.gemspec"))
  end
end
