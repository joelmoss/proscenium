# frozen_string_literal: true

class UILayout < ApplicationView
  include Phlex::Rails::Helpers::CSPMetaTag
  include Phlex::Rails::Helpers::CSRFMetaTags

  def around_template(&block)
    doctype

    html do
      head do
        title { 'Proscenium UI' }
        meta name: 'viewport', content: 'width=device-width,initial-scale=1'
        csp_meta_tag
        csrf_meta_tags
        include_assets
      end

      body do
        super
      end
    end
  end
end
