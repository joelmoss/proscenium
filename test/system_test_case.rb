# frozen_string_literal: true

require 'test_helper'
require 'capybara/cuprite'

Capybara.default_max_wait_time = 5
Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

# Reduce extra logs produced by puma booting up
Capybara.server = :puma, { Silent: true }

class SystemTestCase < ActionDispatch::SystemTestCase
  include Capybara::Minitest::Assertions
  driven_by :cuprite, using: :chrome # , screen_size: [1400, 1400]

  teardown do
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end
