# frozen_string_literal: true

class PhlexController < ApplicationController
  layout -> { Views::Layouts::Application }

  def basic
    render Views::Phlex::Basic.new
  end
end
