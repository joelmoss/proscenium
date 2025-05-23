# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'
ENV['PROSCENIUM_TESTS'] = '1'

require_relative '../fixtures/dummy/config/environment'
require 'rails/test_help'
require 'maxitest/autorun'

DatabaseCleaner.strategy = :transaction

module ActiveSupport
  class TestCase
    around do |tests|
      DatabaseCleaner.cleaning(&tests)
    end

    before do
      Proscenium.config.side_load = true
      Proscenium::Importer.reset
      Proscenium::Resolver.reset
    end

    class << self
      alias with context
    end
  end
end

module ViewHelper
  def self.extended(parent)
    parent.class_exec do
      delegate :view_context, to: :controller

      def controller
        @controller ||= ActionView::TestCase::TestController.new
      end
    end
  end

  def view(obj, &blk)
    let :instance do
      instance_exec(&obj)
    end

    let :view do
      result = if blk
                 instance.call(view_context:) do
                   instance.instance_exec(instance, &blk)
                 end
               else
                 instance.call(view_context:)
               end

      ::Capybara::Node::Simple.new result
    end
  end
end
