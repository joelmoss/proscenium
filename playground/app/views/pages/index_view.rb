# frozen_string_literal: true

class Pages::IndexView < ApplicationLayout
  def view_template
    div class: :@base do
      img src: '/logo.svg', width: 352, height: 72
    end
  end
end
