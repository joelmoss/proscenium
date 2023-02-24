# frozen_string_literal: true

require 'phlex/rails'

# Include this in your view for additional logic for rendering a full HTML page, usually from a
# controller.
module Proscenium::Phlex::Page
  include Phlex::Rails::Layout

  def template(&block)
    doctype
    html do
      head
      body(&block)
    end
  end

  private

  def page_title
    Rails.application.class.name.deconstantize
  end

  def head
    super do
      title { page_title }

      yield if block_given?

      csp_meta_tag
      csrf_meta_tags

      comment { '[SIDE_LOAD_STYLESHEETS]' }
    end
  end

  def body
    super do
      yield if block_given?

      side_load_javascripts defer: true, type: :module
      Rails.env.development? && proscenium_dev
    end
  end

  def html
    super do
      yield

      @_target.gsub!('<!-- [SIDE_LOAD_STYLESHEETS] -->', capture { side_load_stylesheets })
    end
  end
end
