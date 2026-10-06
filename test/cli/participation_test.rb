# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'proscenium/bundled_gems'

# Which installed gems take part (#154, C50): opted in by their author, or by the app in
# package.json's `proscenium` key, and never a gem the app opted out.
describe 'Proscenium::BundledGems participation' do
  BG = Proscenium::BundledGems
  Spec = Struct.new(:name, :metadata, :full_gem_path)

  def spec(name, opted_in: false, frontend_root: nil, manifest: false)
    root = File.join(@dir, name)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'package.json'), '{}') if manifest
    metadata = {}
    metadata['proscenium.dependencies'] = 'true' if opted_in
    metadata['proscenium.frontend_root'] = frontend_root if frontend_root
    Spec.new(name, metadata, root)
  end

  before { @dir = Dir.mktmpdir('participation') }
  after { FileUtils.rm_rf(@dir) }

  def specs
    [spec('actiontext', manifest: true), spec('plain'),
     spec('widget', opted_in: true, manifest: true)]
  end

  it 'takes only the gems their authors opted in' do
    assert_equal %w[widget], BG.participating(specs).keys
  end

  it 'lets the app opt a gem in or out' do
    overrides = { 'actiontext' => true, 'widget' => false }

    assert_equal %w[actiontext], BG.participating(specs, overrides:).keys
  end

  it 'lists gems that ship a package.json but do not take part, such as actiontext' do
    assert_equal %w[actiontext], BG.unparticipating_with_manifest(specs)
  end

  it 'finds the manifest at the root or the frontend root, never outside the gem' do
    root = File.join(@dir, 'widget')

    assert_equal root, BG.manifest_root(spec('widget'))
    nested = spec('widget', frontend_root: './app/js/')

    assert_equal File.join(root, 'app/js'), BG.manifest_root(nested)
    assert_nil BG.manifest_root(spec('widget', frontend_root: '../elsewhere'))
    assert_nil BG.manifest_root(spec('widget', frontend_root: '/etc'))
  end

  describe "package.json's proscenium key" do
    def write(json) = File.write(File.join(@dir, 'package.json'), json)

    it 'is optional, as is package.json' do
      assert_empty BG.overrides(@dir)
      write('{"name": "app"}')

      assert_empty BG.overrides(@dir)
    end

    it 'reads gemOverrides' do
      # With a byte order mark, as Windows editors write one.
      write("\uFEFF{\"name\": \"app\", \"proscenium\": {\"gemOverrides\": " \
            '{"a": {"participate": true}, "b": {"participate": false}}}}')

      assert_equal({ 'a' => true, 'b' => false }, BG.overrides(@dir))
    end

    it 'ignores a proscenium.json, which it no longer reads' do
      File.write(File.join(@dir, 'proscenium.json'),
                 '{"schema": 1, "gemOverrides": {"a": {"participate": true}}}')

      assert_empty BG.overrides(@dir)
    end

    it 'refuses anything else, by name' do
      {
        '{nope' => 'package.json is not valid JSON',
        '[]' => 'package.json does not hold a JSON object',
        '{"proscenium": []}' => '"proscenium" in package.json must be an object',
        '{"proscenium": {"gemOverrides": "x"}}' =>
          '"proscenium.gemOverrides" in package.json must be an object',
        '{"proscenium": {"gemOverrides": {"a": {"participate": "yes"}}}}' =>
          '"proscenium.gemOverrides.a.participate" in package.json must be true or false'
      }.each do |json, message|
        write(json)
        error = assert_raises(BG::ConfigError) { BG.overrides(@dir) }

        assert_includes error.message, message
      end
    end
  end
end
