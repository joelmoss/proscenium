# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'proscenium/context_map'
require 'proscenium/stale_contexts'

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

  # C52: an adopted app whose last participating gem left still builds, with an empty map.
  it 'maps nothing for an adopted app with no participating gem' do
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")

    assert CM.adopted?(@root)
    assert_empty CM.contexts(@root, specs.drop(1))
    assert_nil CM.adoption_notice(@root, specs.drop(1))
  end

  it 'maps nothing for an unreadable proscenium.json, which staleness reports instead' do
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")
    write('proscenium.json', '{"schema": 2}')

    assert_empty CM.contexts(@root, specs)
    assert_equal ['proscenium.json must have "schema": 1'],
                 Proscenium::StaleContexts.problems(@root, specs, [])
  end

  it "takes Bun's registration in package.json only in a Bun app" do
    write('package.json', '{"workspaces": [".proscenium/packages/*"]}')

    refute CM.adopted?(@root), 'a Yarn or npm app with the same line has not adopted'
    write('bun.lock', '{}')

    assert CM.adopted?(@root)
  end

  describe 'installing?' do
    before { FileUtils.mkdir_p(File.join(@root, '.proscenium')) }

    it 'is true while the marker is there' do
      refute CM.installing?(@root)
      write('.proscenium/installing', '1')

      assert CM.installing?(@root)
    end

    it 'is true while another holds the project lock, and never takes it from them' do
      File.open(File.join(@root, '.proscenium/lock'), File::RDWR | File::CREAT) do |io|
        io.flock(File::LOCK_EX)

        assert CM.installing?(@root)
      end

      refute CM.installing?(@root)
    end
  end

  describe 'adoption notice' do
    it 'names the opted-in gems and the command, before adoption' do
      assert_equal 'hue opt in to installing their JavaScript dependencies through Proscenium. ' \
                   'Run `bundle exec proscenium install` to install them.',
                   CM.adoption_notice(@root, specs)
    end

    it 'says Yarn and npm keep managing them' do
      write('yarn.lock', '')

      assert_includes CM.adoption_notice(@root, specs), 'but Yarn is not supported'
    end

    it 'says nothing once adopted, or with no gem opted in' do
      assert_nil CM.adoption_notice(@root, specs.drop(1))
      write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")

      assert_nil CM.adoption_notice(@root, specs)
    end
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
