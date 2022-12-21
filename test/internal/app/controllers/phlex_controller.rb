# frozen_string_literal: true

class PhlexController < ApplicationController
  layout false

  def basic
    render Views::Phlex::Basic.new
  end
end
