# frozen_string_literal: true

require 'test_helper'
require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'

class Proscenium::Phlex::CssModulesTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper
  include Phlex::Testing::Capybara::ViewHelper

  describe 'class attribute' do
    context 'plain class name' do
      it 'should not use css module name' do
        render Phlex::SideLoadCssModuleFromAttributesView.new('base')

        assert page.has_css?('div.base', text: 'Hello')
      end
    end

    context 'css module class name' do
      it 'should use css module name' do
        render Phlex::SideLoadCssModuleFromAttributesView.new(:@base)

        assert page.has_css?('div.base-02dcd653', text: 'Hello')
      end
    end
  end

  describe 'css_module helper' do
    it 'replaces with CSS module name' do
      render Phlex::CssModuleHelperComponent.new

      assert page.has_css?('h1.header-ab5b1c05', text: 'Hello')
    end
  end

  describe 'css_module_path' do
    it 'child inherits parent if child does not exist' do
      father = Phlex::Father.css_module_path
      child = Phlex::Child.css_module_path

      assert_equal father, child
    end
  end

  context 'child and parent css module path' do
    it 'uses child' do
      render Phlex::Father.new

      assert page.has_css?('h1.grandfather-267f8f06', text: 'Grandfather')
    end
  end

  context 'parent and no child css module path' do
    it 'uses parent' do
      render Phlex::Child.new

      assert page.has_css?('h1.grandfather-267f8f06', text: 'Grandfather')
    end
  end

  context 'child and no parent css module path' do
    it 'uses parent' do
      render Phlex::Grandfather.new

      assert page.has_css?('h1.grandfather-06141f76', text: 'Grandfather')
    end
  end
end
