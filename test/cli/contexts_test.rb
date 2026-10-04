# frozen_string_literal: true

require_relative 'helper'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'proscenium/cli/contexts'

# One gem referencing another's context (#154, C44, C26): kept, as `workspace:*`, only when the
# gemspec depends on the other gem and it participates, so Bundler has locked a compatible
# version. Anything else is a participation error naming both gems, with the consumer's escape.
describe Proscenium::CLI::Contexts do
  Dep = Struct.new(:name)
  ContextSpec = Struct.new(:name, :metadata, :full_gem_path, :runtime_dependencies)

  before { @dir = Dir.mktmpdir('contexts') }
  after { FileUtils.rm_rf(@dir) }

  def spec(name, manifest, depends_on: [])
    root = File.join(@dir, name)
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'package.json'), JSON.generate(manifest))
    ContextSpec.new(name, { 'proscenium.dependencies' => 'true' }, root,
                    depends_on.map { Dep.new(it) })
  end

  def contexts(*specs) = Proscenium::CLI::Contexts.new(@dir, specs.to_h { [it.name, it] })

  def context(contexts, gem) = JSON.parse(contexts.contexts.fetch(gem).json)

  def codes(contexts) = contexts.problems.map(&:first)

  let(:core) { spec('core', {}) }

  it 'rewrites a reference to a participating gem the gemspec depends on to workspace:*' do
    ui = spec('ui', { 'dependencies' => { '@rubygems/core' => '^1.2.0' },
                      'peerDependencies' => { '@rubygems/core' => '>= 1' } }, depends_on: %w[core])
    result = contexts(ui, core)

    assert_empty result.problems
    assert_equal({ '@rubygems/core' => 'workspace:*' }, context(result, 'ui')['dependencies'])
    assert_equal({ '@rubygems/core' => 'workspace:*' }, context(result, 'ui')['peerDependencies'])
  end

  it 'refuses a reference without the gemspec dependency, naming both gems, with the escape' do
    ui = spec('ui', { 'dependencies' => { '@rubygems/core' => '^1.2.0' } })
    result = contexts(ui, core)

    assert_equal ['PSM-E-CROSS-GEM'], codes(result)
    assert_equal %w[ui core], result.problems.first.last.values_at(:gem, :other)
    assert_includes result.problems.first.last[:escape], '"gemOverrides": {"ui"'
    refute result.contexts.key?('ui')
  end

  it 'refuses a reference to a gem that does not participate, or is absent' do
    ui = spec('ui', { 'dependencies' => { '@rubygems/core' => '^1.2.0' } }, depends_on: %w[core])

    assert_equal ['PSM-E-CROSS-GEM-TARGET'], codes(contexts(ui))
  end

  it 'links an optional peer when its gem participates, and leaves it out otherwise' do
    manifest = { 'peerDependencies' => { '@rubygems/core' => '>= 1' },
                 'peerDependenciesMeta' => { '@rubygems/core' => { 'optional' => true } } }
    ui = spec('ui', manifest, depends_on: %w[core])

    assert_equal({ '@rubygems/core' => 'workspace:*' },
                 context(contexts(ui, core), 'ui')['peerDependencies'])
    assert_nil context(contexts(ui), 'ui')['peerDependencies']
  end

  # C26: a gem cannot reach outside itself through file: or link:, contained or not.
  it "refuses a gem's file: and link: references, with the escape" do
    ui = spec('ui', { 'dependencies' => { 'inside' => 'file:./vendor/inside',
                                          'outside' => 'link:../../elsewhere' } })
    result = contexts(ui)

    assert_equal %w[PSM-E-SPEC PSM-E-SPEC], codes(result)
    assert(result.problems.all? { it.last[:escape].include?('proscenium.json') })
  end
end
