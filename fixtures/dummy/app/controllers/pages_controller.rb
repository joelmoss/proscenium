# frozen_string_literal: true

class PagesController < ApplicationController
  layout 'application'

  def variant
    request.variant = :mobile
  end
end
