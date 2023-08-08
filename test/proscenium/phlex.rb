# frozen_string_literal: true

require 'phlex/testing/rails/view_helper'

describe Proscenium::Phlex do
  include Phlex::Testing::Rails::ViewHelper

  def before
    Proscenium::Importer.reset
    Proscenium::Resolver.reset
  end

  it 'side loads component js and css' do
    render Phlex::SideLoadView.new

    expect(Proscenium::Importer.imported).to be == {
      '/app/components/phlex/side_load_view.css' => { sideloaded: true },
      '/app/components/phlex/side_load_view.js' => { sideloaded: true }
    }
  end

  it 'nested side load' do
    render Phlex::NestedSideLoadView.new

    expect(Proscenium::Importer.imported).to be == {
      '/app/components/phlex/nested_side_load_view.css' => { sideloaded: true },
      '/app/components/phlex/side_load_view.css' => { sideloaded: true },
      '/app/components/phlex/side_load_view.js' => { sideloaded: true }
    }
  end
end
