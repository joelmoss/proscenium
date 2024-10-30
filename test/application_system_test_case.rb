# frozen_string_literal: true

require 'test_helper'
require 'capybara/rails'
require 'capybara/cuprite'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite, using: :chrome, screen_size: [1400, 1400], options: { js_errors: true }
end

Capybara.default_max_wait_time = 5
Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

Capybara.configure do |config|
  config.server = :puma, { Silent: true }
end

# Capybara.register_driver :cuprite do |app|
#   Capybara::Cuprite::Driver.new(
#     app,
#     # Enable debugging by setting the INSPECTOR environment variable to true, and inserting the
#     # following into the code you want to debug:
#     #
#     #   page.driver.debug(binding)
#     inspector: ENV.fetch('INSPECTOR', nil),
#     logger: SystemTesting::ConsoleLogger.new
#   )
# end

# class Capybara::Session
#   def console_logs
#     driver.browser.options.logger.logs
#   end

#   def console_messages
#     driver.browser.options.logger.messages
#   end
# end
