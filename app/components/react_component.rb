# frozen_string_literal: true

class ReactComponent < ApplicationComponent
  attr_accessor :props

  def initialize(props = {})
    @props = props
    super
  end

  def call
    tag.div data: { component: { path: virtual_path, props: @props } }
  end
end
