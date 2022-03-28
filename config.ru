# frozen_string_literal: true

require 'rubygems'
require 'bundler'

ENV['RAILS_ENV'] = 'development'
ENV['PROSCENIUM_TEST'] = 'test'

Bundler.require :default, ENV['RAILS_ENV'].to_sym

Combustion.path = 'test/internal'
Combustion.initialize! :action_controller, :action_view do
  config.consider_all_requests_local = false
end
run Combustion::Application
