# frozen_string_literal: true

class CodeStageComponent < ApplicationComponent
  def template(&block)
    div class: :@base do
      div(&block)
    end
  end
end
