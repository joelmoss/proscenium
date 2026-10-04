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

    assert_equal ['hue: its JavaScript dependencies changed since its context was written'],
                 problems

    write_context('hue', '{"dependencies": {"ms": "^3.0.0"}}')
    path = File.join(@root, '.proscenium/packages/hue/package.json')
    File.write(path, File.read(path).gsub('  ', '    '))

    assert_empty problems
  end

  it 'finds a participating gem with no context' do
    widget = gem_spec('widget', '{}')

    assert_equal ['widget: it has no committed context'], problems([@hue, widget])
  end

  it 'finds a context whose gem left the lock or stopped participating, keeping an excluded one' do
    write_context('gone', '{}')
    write_context('dev_only', '{}')

    assert_equal ['gone: its context belongs to no participating gem'],
                 problems([@hue], %w[hue dev_only])
  end

  it 'reports the build error with the command, once per root' do
    SC.reset!
    message = SC.message(@root) # this process's bundle has no hue, so its context is an orphan

    assert_equal "Gem dependency contexts are out of date:\n  " \
                 "- hue: its context belongs to no participating gem\n" \
                 'Run `bundle exec proscenium install` and commit .proscenium/packages.', message
    FileUtils.rm_rf(File.join(@root, '.proscenium'))

    assert_same message, SC.message(@root)
  ensure
    SC.reset!
  end
end
