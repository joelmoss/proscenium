# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Phlexible::Rails::ActionController::ImplicitRender
  layout false
  sideload_assets js: { type: 'module' }
end
