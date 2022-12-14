# frozen_string_literal: true

require 'phlex/rails'

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

      if block_given?
        yield
      else
        meta name: 'viewport', content: 'width=device-width,initial-scale=1'
        csp_meta_tag
        csrf_meta_tags
      end

      comment { '[SIDE_LOAD_STYLESHEETS]' }
    end
  end

  def body
    super do
      yield

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
