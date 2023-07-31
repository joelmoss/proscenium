# frozen_string_literal: true

require_relative '../test_helper'

class Proscenium::Phlex::SideLoadTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper

  setup do
    Proscenium::Importer.reset
  end

  test 'side load component js and css' do
    render Phlex::SideLoadView.new

    assert_equal({
                   '/app/components/phlex/side_load_view.css' => { sideloaded: true },
                   '/app/components/phlex/side_load_view.js' => { sideloaded: true }
                 }, Proscenium::Importer.imported)
  end

  test 'nested side load' do
    render Phlex::NestedSideLoadView.new

    assert_equal({
                   '/app/components/phlex/nested_side_load_view.css' => { sideloaded: true },
                   '/app/components/phlex/side_load_view.css' => { sideloaded: true },
                   '/app/components/phlex/side_load_view.js' => { sideloaded: true }
                 }, Proscenium::Importer.imported)
  end
end
