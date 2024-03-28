# frozen_string_literal: true

class Pages::IndexView < ApplicationLayout
  def template
    div class: :@base do
      img src: '/logo.svg', width: 352, height: 72
    end
  end
end
