# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'proscenium/stale_contexts'

# When an adopted app's committed contexts no longer match its bundle (#154, C36, C45-C): the
# engine refuses to build until `proscenium install` runs.
describe Proscenium::StaleContexts do
  SC = Proscenium::StaleContexts
  StaleSpec = Struct.new(:name, :metadata, :full_gem_path, :runtime_dependencies)

  before do
    @root = Dir.mktmpdir('stale')
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")
    @hue = gem_spec('hue', '{"dependencies": {"ms": "^2.1.3"}}')
    write_context('hue', '{"dependencies": {"ms": "^2.1.3"}}')
  end

  after { FileUtils.rm_rf(@root) }

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), body)
  end

  def gem_spec(name, manifest)
    write("gems/#{name}/package.json", manifest)
    StaleSpec.new(name, { 'proscenium.dependencies' => 'true' }, File.join(@root, 'gems', name), [])
  end

  # The context `install` writes for `manifest`.
  def write_context(gem, manifest)
    context = Proscenium::DependencyContext.project(gem, JSON.parse(manifest))
    write(".proscenium/packages/#{gem}/package.json", Proscenium::DependencyContext.to_json(context))
  end

  def problems(specs = [@hue], locked = specs.map(&:name)) = SC.problems(@root, specs, locked)

  it 'finds nothing when every context is current, or before adoption' do
    assert_empty problems
    File.delete(File.join(@root, 'pnpm-workspace.yaml'))
    write_context('hue', '{"dependencies": {"ms": "^1.0.0"}}')

    assert_empty problems
  end

  it 'finds a gem whose dependencies changed, and ignores reformatting its context' do
    write('gems/hue/package.json', '{"dependencies": {"ms": "^3.0.0"}}')

    assert_equal ['hue: its NPM dependencies changed since its dependency context was ' \
                  'written'],
                 problems

    write_context('hue', '{"dependencies": {"ms": "^3.0.0"}}')
    path = File.join(@root, '.proscenium/packages/hue/package.json')
    File.write(path, File.read(path).gsub('  ', '    '))

    assert_empty problems
  end

  # The engine counts a registration it cannot parse, so as not to switch off; it says so, and
  # refuses, rather than build against whatever is installed.
  it 'reports a pnpm-workspace.yaml that is not valid YAML' do
    write('pnpm-workspace.yaml', "packages: [.proscenium/packages/*\n")

    assert_equal 1, problems.size
    assert_match(/\Apnpm-workspace.yaml: it is not valid YAML/, problems.first)
  end

  # A Bun app registers in package.json; a broken pnpm-workspace.yaml left from before is not read.
  it 'ignores a pnpm-workspace.yaml in an app Bun installs' do
    write('pnpm-workspace.yaml', "packages: [.proscenium/packages/*\n")
    write('package.json', '{"workspaces": [".proscenium/packages/*"]}')
    write('bun.lock', '{}')

    assert_empty problems
  end

  # A context directory without its package.json, or with one that is not JSON, is reported by
  # name. Raising instead would fail every build with an error that says nothing about the cause.
  it 'reports a missing or unreadable committed context instead of raising' do
    path = File.join(@root, '.proscenium/packages/hue/package.json')
    File.delete(path)

    assert_equal ["hue: its dependency context hasn't been written yet"], problems

    ['{not json', '[]', '{"proscenium": "x"}'].each do |text|
      File.write(path, text)

      assert_equal ['hue: its dependency context is not valid JSON'], problems, text
    end
  end

  # A context from another projection version always hashes differently; it was not hand-edited.
  it 'finds a context written by another version of Proscenium' do
    path = File.join(@root, '.proscenium/packages/hue/package.json')
    File.write(path, File.read(path).sub('dependency-context-v1', 'dependency-context-v0'))

    assert_equal ['hue: its dependency context was written by a different version of Proscenium'],
                 problems
  end

  # The hash a context reports about itself is not trusted: an edit that changes its dependencies
  # but keeps the hash would otherwise build against a graph no install produced.
  it 'finds a context edited by hand, even when its reported hash is unchanged' do
    path = File.join(@root, '.proscenium/packages/hue/package.json')
    File.write(path, File.read(path).sub('^2.1.3', '^9.0.0'))

    assert_equal ['hue: its dependency context was edited by hand'], problems
  end

  # The generated name is the context's workspace identity, which other contexts' `workspace:*`
  # edges and a production install's filter name; the hash does not cover it.
  it 'finds a context whose generated fields were edited by hand' do
    path = File.join(@root, '.proscenium/packages/hue/package.json')
    original = File.read(path)
    [original.sub('@rubygems/hue', '@rubygems/other'), original.sub('true', 'false'),
     original.sub('Do not edit', 'Edit'), original.sub('"name"', '"main": "x.js", "name"')]
      .each do |edited|
      File.write(path, edited)

      assert_equal ['hue: its dependency context was edited by hand'], problems, edited
    end
  end

  it 'reports a gem whose manifest has a field of the wrong type instead of raising' do
    write('gems/hue/package.json', '{"dependencies": "x"}')

    assert_match(/hue's package.json can't be used, because dependencies is not an object/,
                 problems.join)
  end

  # C36: editing a path gem's frontend files needs no install; dropping its manifest does, and
  # withdrawing participation orphans its context.
  it "ignores an edit to a gem's assets, but not a dropped manifest or withdrawn participation" do
    write('gems/hue/index.js', 'export default 2')

    assert_empty problems

    File.delete(File.join(@root, 'gems/hue/package.json'))

    assert_equal 1, problems.size
    assert_includes problems.first, 'package.json'

    @hue.metadata = {}

    assert_equal [format(SC::ORPHAN, gem: 'hue')], problems
  end

  it 'finds a participating gem with no context' do
    widget = gem_spec('widget', '{}')

    assert_equal ["widget: its dependency context hasn't been written yet"],
                 problems([@hue, widget])
  end

  it 'finds a context whose gem left the lock or stopped participating, keeping an excluded one' do
    write_context('gone', '{}')
    write_context('dev_only', '{}')

    assert_equal [format(SC::ORPHAN, gem: 'gone')],
                 problems([@hue], %w[hue dev_only])
  end

  it 'finds a shared peer the gem and the app reach as two copies' do
    manifest = '{"peerDependencies": {"react": "^18.0.0"}}'
    hue = gem_spec('hue', manifest)
    write_context('hue', manifest)
    write('package.json', '{"dependencies": {"react": "18.3.1"}}')
    write('node_modules/react/package.json', '{}')

    assert_empty problems([hue])

    write('.proscenium/packages/hue/node_modules/react/package.json', '{}')

    assert_equal 1, problems([hue]).size
    assert_includes problems([hue]).first, 'hue and your app use different copies of react'
  end

  it 'reports the build error with the command, once per root' do
    SC.reset!
    message = SC.message(@root) # this process's bundle has no hue, so its context is an orphan

    assert_equal "Gem dependency contexts are out of date:\n  " \
                 "- #{format(SC::ORPHAN, gem: 'hue')}\n" \
                 'Run `bundle exec proscenium install` and commit .proscenium/packages.', message
    FileUtils.rm_rf(File.join(@root, '.proscenium'))

    assert_same message, SC.message(@root)
  ensure
    SC.reset!
  end
end
