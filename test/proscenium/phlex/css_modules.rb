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

  it 'should not use css module name' do
    render Phlex::SideLoadCssModuleFromAttributesView.new('base')

    expect(page.has_css?('div.base', text: 'Hello')).to be == true
  end

  it 'should use css module name' do
    render Phlex::SideLoadCssModuleFromAttributesView.new(:@base)

    expect(page.has_css?('div.base02dcd653', text: 'Hello')).to be == true
  end

  it 'should raise when css_module class is used but stylesheet does not exist' do
    skip 'needed?'

    expect do
      render Phlex::Plain.new(:@base)
    end.to raise_exception(Proscenium::CssModule::StylesheetNotFound)
  end

  it 'should side load css module when bare path is given' do
    render Phlex::SideLoadCssModuleFromAttributesView.new('mypackage/foo@foo')

    expect(page.has_css?('div.foo39337ba7', text: 'Hello')).to be == true
    expect(Proscenium::Importer.imported).to be == {
      '/app/components/phlex/side_load_css_module_from_attributes_view.module.css' => {
        sideloaded: true, digest: '02dcd653'
      },
      '/packages/mypackage/foo.module.css' => { digest: '39337ba7' }
    }
  end

  it 'should side load css module when absolute path is given' do
    render Phlex::SideLoadCssModuleFromAttributesView.new('/lib/styles@my_class')

    expect(page.has_css?('div.myClass330940eb', text: 'Hello')).to be == true
    expect(Proscenium::Importer.imported).to be == {
      '/app/components/phlex/side_load_css_module_from_attributes_view.module.css' => {
        sideloaded: true, digest: '02dcd653'
      },
      '/lib/styles.module.css' => { digest: '330940eb' }
    }
  end

  it 'should raise when path is given but stylesheet does not exist' do
    expect do
      render Phlex::SideLoadCssModuleFromAttributesView.new('/unknown@my_class')
    end.to raise_exception Proscenium::Builder::ResolveError
  end
end
