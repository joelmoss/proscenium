# frozen_string_literal: true

require 'phlex/testing/rails/view_helper'
require 'phlex/testing/capybara'

describe Proscenium::Phlex::CssModules do
  include Phlex::Testing::Rails::ViewHelper
  include Phlex::Testing::Capybara::ViewHelper

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  describe 'class attribute' do
    with 'plain class name' do
      it 'should not use css module name' do
        render Phlex::SideLoadCssModuleFromAttributesView.new('base')

        expect(page.has_css?('div.base', text: 'Hello')).to be == true
      end
    end

    with 'css module class name' do
      it 'should use css module name' do
        render Phlex::SideLoadCssModuleFromAttributesView.new(:@base)

        expect(page.has_css?('div.base-02dcd653', text: 'Hello')).to be == true
      end
    end
  end

  describe 'css_module helper' do
    it 'replaces with CSS module name' do
      render Phlex::CssModuleHelperComponent.new

      expect(page.has_css?('h1.header-ab5b1c05', text: 'Hello')).to be == true
    end
  end

  describe 'css_module_path' do
    it 'child inherits parent if child does not exist' do
      father = Phlex::Father.css_module_path
      child = Phlex::Child.css_module_path

      expect(father).to be == child
    end
  end

  with 'child and parent css module path' do
    it 'uses child' do
      render Phlex::Father.new

      expect(page.has_css?('h1.grandfather-267f8f06', text: 'Grandfather')).to be == true
    end
  end

  with 'parent and no child css module path' do
    it 'uses parent' do
      render Phlex::Child.new

      expect(page.has_css?('h1.grandfather-267f8f06', text: 'Grandfather')).to be == true
    end
  end

  with 'child and no parent css module path' do
    it 'uses parent' do
      render Phlex::Grandfather.new

      expect(page.has_css?('h1.grandfather-06141f76', text: 'Grandfather')).to be == true
    end
  end
end
