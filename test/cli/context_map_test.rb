# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'proscenium/context_map'

# What the engine tells Go about gem dependency contexts (#154, Stage C): nothing until the app
# adopts them, then a context for every participating gem, and the app's own local packages.
describe Proscenium::ContextMap do
  CM = Proscenium::ContextMap
  GemSpec = Struct.new(:name, :metadata, :full_gem_path)

  before { @root = Dir.mktmpdir('context_map') }
  after { FileUtils.rm_rf(@root) }

  def write(path, body) = File.write(File.join(@root, path), body)

  def specs
    [GemSpec.new('hue', { 'proscenium.dependencies' => 'true' }, '/gems/hue'),
     GemSpec.new('rails', {}, '/gems/rails')]
  end

  it 'maps nothing before the app adopts contexts' do
    write('package.json', '{"name": "app"}')

    refute CM.adopted?(@root)
    assert_empty CM.contexts(@root, specs)
  end

  it "maps every participating gem once pnpm's workspace file registers them" do
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")

    assert_equal({ 'hue' => File.join(@root, '.proscenium/packages/hue') },
                 CM.contexts(@root, specs))
  end

  it "takes Bun's registration in package.json only in a Bun app" do
    write('package.json', '{"workspaces": [".proscenium/packages/*"]}')

    refute CM.adopted?(@root), 'a Yarn or npm app with the same line has not adopted'
    write('bun.lock', '{}')

    assert CM.adopted?(@root)
  end

  it "lists the app's own link:, file: and workspace packages" do
    write('package.json', JSON.generate(
                            'dependencies' => { 'mine' => 'link:vendor/mine', 'react' => '18.3.1' },
                            'devDependencies' => { 'tools' => 'file:../tools',
                                                   'sibling' => 'workspace:*' }
                          ))

    assert_equal %w[mine sibling tools], CM.local_packages(@root)
  end
end
