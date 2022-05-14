# frozen_string_literal: true

require 'test_helper'

class ProsceniumTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Proscenium::VERSION
  end

  def test_default_middleware_config
    assert_equal %i[runtime static], Rails.application.config.proscenium.middleware
  end
end
