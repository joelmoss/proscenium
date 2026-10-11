# frozen_string_literal: true

require 'test_helper'

# `CssModule::Path` is extended by component classes in proscenium-phlex and
# proscenium-view_component, so its lookup is public API: a class's own `.module.css` beside its
# source file, else the nearest ancestor's, with the walk ending at an abstract class or at one
# that does not take part.
describe Proscenium::CssModule::Path do
  before { @dir = Pathname.new(Dir.mktmpdir) }
  after { FileUtils.rm_rf @dir }

  # A class whose source file is `<name>.rb` in the test's directory, and which has a CSS module
  # beside it when `css_module` is true.
  def component(name, parent: Object, abstract: false, css_module: false)
    FileUtils.touch @dir.join("#{name}.module.css") if css_module
    source = @dir.join("#{name}.rb")
    Class.new(parent) do
      extend Proscenium::CssModule::Path

      define_singleton_method(:source_path) { source }
      define_singleton_method(:abstract_class) { abstract }
    end
  end

  it "is the class's own CSS module" do
    klass = component('own', css_module: true)

    assert_equal @dir.join('own.module.css'), klass.css_module_path
  end

  it "is the nearest ancestor's when the class has none" do
    grandparent = component('grandparent', css_module: true)
    parent = component('parent', parent: grandparent)
    child = component('child', parent:)

    assert_equal @dir.join('grandparent.module.css'), child.css_module_path
  end

  it 'stops at an abstract ancestor, without looking above it' do
    grandparent = component('grandparent', css_module: true)
    parent = component('parent', parent: grandparent, abstract: true, css_module: true)
    child = component('child', parent:)

    assert_nil child.css_module_path
  end

  it 'is nil when no class in the chain has one' do
    parent = component('parent')
    child = component('child', parent:)

    assert_nil child.css_module_path
  end
end
