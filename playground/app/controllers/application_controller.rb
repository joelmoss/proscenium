# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Phlexible::Rails::ActionController::ImplicitRender
  layout false
end
