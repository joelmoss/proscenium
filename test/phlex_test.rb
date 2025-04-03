# frozen_string_literal: true

require 'test_helper'
require 'phlex/testing/rails/view_helper'

class Proscenium::PhlexTest < ActiveSupport::TestCase
  include Phlex::Testing::Rails::ViewHelper

  it 'side loads component js and css' do
    render Phlex::SideLoadView.new

    assert_equal({
                   '/app/components/phlex/side_load_view.css' => {},
                   '/app/components/phlex/side_load_view.js' => {}
                 }, Proscenium::Importer.imported)
  end

  test 'nested side load' do
    render Phlex::NestedSideLoadView.new

    assert_equal({
                   '/app/components/phlex/nested_side_load_view.css' => {},
                   '/app/components/phlex/side_load_view.css' => {},
                   '/app/components/phlex/side_load_view.js' => {}
                 }, Proscenium::Importer.imported)
  end
end
