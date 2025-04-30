# frozen_string_literal: true

require 'test_helper'
require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'

class Proscenium::CssModule::RewriterTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper
  include Phlex::Testing::Capybara::ViewHelper

  context 'with superclass css module path' do
    it 'rewrites class name beginning with @' do
      rewrite 'single_class'
      render Phlex::CssModuleRewriter::SingleClass

      assert page.has_css?('div.title-7d8c062a', text: 'Hello')
    end

    it 'rewrites multiple class names beginning with @' do
      rewrite 'multiple_classes'
      render Phlex::CssModuleRewriter::MultipleClasses

      assert page.has_css?('div.title-7d8c062a.another_class', text: 'Hello')
    end

    it 'does not rewrite class names without with @' do
      rewrite 'non_css_module'
      render Phlex::CssModuleRewriter::NonCssModule

      assert page.has_css?('div.title', text: 'Hello')
    end
  end

  it 'uses class css module path' do
    rewrite 'class_css_module'
    render Phlex::CssModuleRewriter::ClassCssModule

    assert page.has_css?('div.title-9fe1148d', text: 'Hello')
  end

  it 'uses custom css_module_path' do
    rewrite 'css_module_path'
    render Phlex::CssModuleRewriter::CssModulePath

    assert page.has_css?('div.title-9fe1148d', text: 'Hello')
  end

  private

  def rewrite(filename)
    Proscenium::CssModule::Rewriter.init(
      include: [Rails.root.join('app', 'components', 'phlex',
                                'css_module_rewriter').to_s + "/#{filename}.rb"]
    )
  end
end
