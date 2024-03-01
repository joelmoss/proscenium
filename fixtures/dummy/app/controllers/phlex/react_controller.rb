# frozen_string_literal: true

class Phlex::ReactController < ApplicationController
  def forward_children
    render(Phlex::React::ForwardChildren::Component.new { 'hello' })
  end
end
