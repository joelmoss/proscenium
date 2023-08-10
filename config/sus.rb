# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require_relative 'sus/include'

Bundler.require :default, :test

require 'proscenium'
require_relative '../fixtures/dummy/config/environment'
