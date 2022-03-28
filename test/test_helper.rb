# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'
ENV['PROSCENIUM_TEST'] = 'test'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'proscenium'
require 'maxitest/autorun'
require 'minitest/heat'
require 'combustion'

Combustion.path = 'test/internal'
Combustion.initialize! :action_controller, :action_view do
  config.consider_all_requests_local = false
end

class ActiveSupport::TestCase
  def before_setup
    @snapshot_dir ||= File.expand_path('test/snapshots')
    super
  end
end
