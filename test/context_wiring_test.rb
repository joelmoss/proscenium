# frozen_string_literal: true

require 'test_helper'

# A wiring test, not a conformance row (#154, Stage C): Builder sends Go the context map Ruby built
# from the bundle, with no DependencyContexts override, and Go resolves the gem's dependency from
# its context. It catches a renamed config key, or the map read from the wrong root.
class Proscenium::ContextWiringTest < ActiveSupport::TestCase
  GEM = 'stage_a_widget_a'
  GEM_ROOT = File.expand_path('package_manager/stage_a/gems/stage_a_widget_a', __dir__)
  Spec = Struct.new(:name, :metadata, :full_gem_path, :runtime_dependencies)

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
    File.write(File.join(@root, path), body)
  end

  def stub(object, name, value)
    object.singleton_class.alias_method(:"real_#{name}", name)
    object.define_singleton_method(name) { |*| value }
  end

  def unstub(object, name)
    object.singleton_class.alias_method(name, :"real_#{name}")
  end

  before do
    @root = File.realpath(Dir.mktmpdir('wiring'))
    write('pnpm-workspace.yaml', "packages:\n  - .proscenium/packages/*\n")
    manifest = JSON.parse(File.read(File.join(GEM_ROOT, 'package.json')))
    context = Proscenium::DependencyContext.project(GEM, manifest)
    write(".proscenium/packages/#{GEM}/package.json", Proscenium::DependencyContext.to_json(context))
    write(".proscenium/packages/#{GEM}/node_modules/ms/package.json", '{"main": "index.js"}')
    write(".proscenium/packages/#{GEM}/node_modules/ms/index.js",
          'export default () => "ms from the context"')
    write('node_modules/react/package.json', '{"main": "index.js"}')
    write('node_modules/react/index.js', 'export default { createElement() {} }')

    stub(Proscenium::ContextMap, :project_root, @root)
    stub(Proscenium::BundledGems, :installed_specs,
         [Spec.new(GEM, { 'proscenium.dependencies' => 'true' }, GEM_ROOT, [])])
    [Proscenium::ContextMap, Proscenium::StaleContexts, Proscenium::MappingGeneration].each(&:reset!)
  end

  after do
    unstub(Proscenium::ContextMap, :project_root)
    unstub(Proscenium::BundledGems, :installed_specs)
    [Proscenium::ContextMap, Proscenium::StaleContexts, Proscenium::MappingGeneration].each(&:reset!)
    FileUtils.rm_rf(@root)
  end

  it "resolves the gem's dependency from the context Ruby mapped" do
    result = Proscenium::Builder.build_to_string("node_modules/@rubygems/#{GEM}/index.js",
                                                 root: @root, RubyGems: { GEM => GEM_ROOT })

    assert_includes result[:response], 'ms from the context'
  end
end
