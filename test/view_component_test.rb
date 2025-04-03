# frozen_string_literal: true

require 'test_helper'

class Proscenium::ViewComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test 'side loads component js and css' do
    render_inline ViewComponent::FirstComponent.new

    assert_equal({
                   '/app/components/view_component/first_component.js' => {},
                   '/app/components/view_component/first_component.css' => {}
                 }, Proscenium::Importer.imported)
  end
end
