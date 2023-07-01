# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'
ENV['PROSCENIUM_TEST'] = 'test'

require_relative '../test/dummy/config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  def before_setup
    @snapshot_dir ||= File.expand_path('test/snapshots')
    super
  end
end
