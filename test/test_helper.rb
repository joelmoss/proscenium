# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'proscenium'
require 'minitest/autorun'
require 'combustion'

Combustion.path = 'test/internal'
Combustion.initialize! :action_controller, :action_view
