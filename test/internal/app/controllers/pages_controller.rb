# frozen_string_literal: true

class PagesController < ApplicationController
  layout 'application'

  def action_rendered_component
    render BasicReactComponent.new
  end
end
