# frozen_string_literal: true

require 'capybara/rails'
require 'capybara/cuprite'
require_relative 'system_testing/console_logger'

Capybara.register_driver :cuprite do |app|
  Capybara::Cuprite::Driver.new(
    app,
    # Enable debugging by setting the INSPECTOR environment variable to true, and inserting the
    # following into the code you want to debug:
    #
    #   page.driver.debug(binding)
    inspector: ENV.fetch('INSPECTOR', nil),
    logger: SystemTesting::ConsoleLogger.new
  )
end

Capybara.default_max_wait_time = 5
Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

# Reduce extra logs produced by puma booting up
Capybara.server = :puma, { Silent: true }

# Include into any `describe` or `with` block with `include_context SystemTest`.
SystemTest = Sus::Shared('system test') do
  include Capybara::DSL

  def after
    super
    Capybara.reset_sessions!
  end
end

class Capybara::Session
  def console_logs
    driver.browser.options.logger.logs
  end

  def console_messages
    driver.browser.options.logger.messages
  end
end
