# frozen_string_literal: true

require_relative './test_helper'

class ViewComponentTest < ViewComponent::TestCase
  include Rails::Dom::Testing::Assertions::DomAssertions

  setup do
    Proscenium.reset_current_side_loaded
  end

  test 'with dry initializer' do
    result = render_inline ViewComponent::DryInitializerComponent.new

    assert_matches_snapshot result.to_html
  end
end
