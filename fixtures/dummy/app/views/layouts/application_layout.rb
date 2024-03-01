# frozen_string_literal: true

class ApplicationLayout < ApplicationView
  include Phlex::Rails::Layout

  def template(&block)
    doctype

    html do
      head do
        title { "You're awesome" }
        meta name: 'viewport', content: 'width=device-width,initial-scale=1'
        csp_meta_tag
        csrf_meta_tags
        include_assets
      end

      body do
        main(&block)
      end
    end
  end
end
