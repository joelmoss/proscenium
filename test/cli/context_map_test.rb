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

  it 'maps nothing for unreadable overrides in package.json, which staleness reports instead' do
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")
    write('package.json', '{"proscenium": {"gemOverrides": "x"}}')

    assert_empty CM.contexts(@root, specs)
    assert_equal ['"proscenium.gemOverrides" in package.json must be an object'],
                 Proscenium::StaleContexts.problems(@root, specs, [])
  end

  # Not only while bun.lock is there: an adopted Bun app missing it is an incomplete checkout,
  # which must not silently switch the contexts off.
  it "takes Bun's registration in package.json, but not in a Yarn or npm app" do
    write('package.json', '{"workspaces": [".proscenium/packages/*"]}')

    assert CM.adopted?(@root), 'a Bun app without its bun.lock'
    write('yarn.lock', '')

    refute CM.adopted?(@root), 'a Yarn app with the same line has not adopted'
    File.delete(File.join(@root, 'yarn.lock'))
    write('pnpm-lock.yaml', '')

    refute CM.adopted?(@root), 'pnpm registers through pnpm-workspace.yaml, never package.json'
  end

  # A `!` pattern covering the contexts keeps the manager from installing them, whatever its order.
  it 'does not count a registration that excludes the contexts' do
    write('pnpm-workspace.yaml',
          "packages:\n  - '!.proscenium/packages/*'\n  - .proscenium/packages/*\n")

    refute CM.adopted?(@root)
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n  - '!apps/old'\n")

    assert CM.adopted?(@root)
  end

  # A package.json Ruby cannot parse, such as one with a trailing comma, which Bun reads, counts as
  # registering the contexts only in its `workspaces`, not wherever the pattern appears.
  it "takes a Bun registration from package.json's workspaces even when Ruby cannot parse it" do
    write('bun.lock', '{}')
    write('package.json', '{"scripts": {"ls": "ls .proscenium/packages/*"},}')

    refute CM.adopted?(@root)
    write('package.json', "{\"workspaces\": [\n  \".proscenium/packages/*\",\n],}")

    assert CM.adopted?(@root)
    write('package.json', '{"workspaces": {"packages": [".proscenium/packages/*",]},}')

    assert CM.adopted?(@root)
    # JSON may escape the slashes, as Bun decodes them.
    write('package.json', '{"workspaces": [".proscenium\\/packages\\/*",],}')

    assert CM.adopted?(@root), 'escaped slashes'
    write('package.json', '{"workspaces": [".proscenium\\u002fpackages\\u002F*",],}')

    assert CM.adopted?(@root), 'unicode-escaped slashes'
    # Any JSON escape, in the key or the pattern, as Bun decodes it.
    write('package.json', '{"worksp\\u0061ces": [".proscenium/packages/\\u002a"],}')

    assert CM.adopted?(@root), 'unicode escapes anywhere'
    # An emoji is a surrogate pair of escapes, and a lone half is legal JSON too: neither raises.
    write('package.json', '{"description": "\\ud83d\\ude00 \\udc00", ' \
                          '"workspaces": [".proscenium/packages/*"],}')

    assert CM.adopted?(@root), 'surrogate escapes'
  end

  # bun.lockb is Bun's lockfile as much as bun.lock is, so a pnpm registration beside it is a
  # leftover; Bun's own registration still counts.
  it 'takes bun.lockb as Bun installing the app' do
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")
    write('bun.lockb', '')

    refute CM.adopted?(@root)
    File.delete(File.join(@root, 'pnpm-workspace.yaml'))
    write('package.json', '{"workspaces": [".proscenium/packages/*"]}')

    assert_equal 'package.json', CM.registrar(@root)
  end

  # The same for pnpm's registration: a leftover pnpm-workspace.yaml in an app another manager now
  # installs is not read, while a pnpm app missing its pnpm-lock.yaml is an incomplete checkout.
  it "takes pnpm's registration, but not in an app another manager installs" do
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")

    assert CM.adopted?(@root), 'a pnpm app without its pnpm-lock.yaml'
    write('bun.lock', '{}')

    refute CM.adopted?(@root), 'a Bun app with a leftover pnpm-workspace.yaml'
    File.delete(File.join(@root, 'bun.lock'))
    write('package.json', '{"packageManager": "bun@1.4.2"}')

    refute CM.adopted?(@root), 'a Bun app by packageManager, with no lockfile yet'
    write('package.json', '{"packageManager": "pnpm@12.9.1"}')

    assert CM.adopted?(@root), 'a pnpm app by packageManager'
    write('package.json', '{}')
    write('.yarnrc.yml', "nodeLinker: node-modules\n")

    refute CM.adopted?(@root), 'a Yarn app by .yarnrc.yml, as Manager.select reads it'
    File.delete(File.join(@root, '.yarnrc.yml'))
    write('bun.lock', '{}')
    write('pnpm-lock.yaml', '')

    assert CM.adopted?(@root)
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
                                                   'sibling' => 'workspace:*' },
                            'peerDependencies' => { 'peer' => 'workspace:^' }
                          ))

    # A local peer too: pnpm installs it into the root node_modules as well.
    assert_equal %w[mine peer sibling tools], Proscenium::AppPackage.local_packages(@root)
  end

  # Bun links a workspace member the app names by an ordinary version range (probed on 1.4.2:
  # `"sibling": "^1.0.0"` became a link to packages/sibling), so it keeps its link path too. pnpm
  # does not, without linkWorkspacePackages, so a pnpm app's members are not read.
  it "lists a Bun app's workspace members it depends on by version" do
    { 'packages/sibling' => 'sibling', 'packages/legacy' => 'legacy',
      'tools/cli' => 'cli' }.each do |dir, name|
      FileUtils.mkdir_p(File.join(@root, dir))
      write("#{dir}/package.json", JSON.generate('name' => name, 'version' => '1.2.0'))
    end
    deps = { 'sibling' => '^1.0.0', 'legacy' => '^1.0.0', 'cli' => '1.2.0', 'react' => '18.3.1' }
    package = { 'workspaces' => ['.proscenium/packages/*', 'packages/*', '!packages/legacy'],
                'dependencies' => deps }
    write('package.json', JSON.generate(package))
    write('bun.lock', '{}')

    assert_equal %w[sibling], Proscenium::AppPackage.local_packages(@root)
    braces = package.merge('workspaces' => { 'packages' => ['{packages,tools}/*'] })
    write('package.json', JSON.generate(braces))

    assert_equal %w[cli legacy sibling], Proscenium::AppPackage.local_packages(@root),
                 'an object form, with braces, and no registration needed'
    File.delete(File.join(@root, 'bun.lock'))
    write('pnpm-lock.yaml', '')

    assert_empty Proscenium::AppPackage.local_packages(@root), 'pnpm links none of them'
  end
end
