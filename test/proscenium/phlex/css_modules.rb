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

      with 'unknown stylesheet' do
        it 'should raise' do
          expect do
            render Phlex::Plain.new(:@base)
          end.to raise_exception(Proscenium::CssModule::StylesheetNotFound)
        end
      end
    end
  end

  with 'css_module helper' do
    it 'replaces with CSS module name' do
      render Phlex::CssModuleHelperComponent.new

      expect(page.has_css?('h1.header-ab5b1c05', text: 'Hello')).to be == true
    end
  end
end
