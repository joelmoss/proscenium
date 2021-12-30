# frozen_string_literal: true

require 'rubygems'
require 'bundler'

ENV['PROSCENIUM_ENV'] = 'development'

Bundler.require :default, ENV['PROSCENIUM_ENV'].to_sym

Combustion.path = 'test/internal'
Combustion.initialize! :action_controller, :action_view
run Combustion::Application
