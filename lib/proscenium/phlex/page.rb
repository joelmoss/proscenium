# frozen_string_literal: true

require 'phlex/rails'

# Include this in your view for additional logic for rendering a full HTML page, usually from a
# controller.
module Proscenium::Phlex::Page
  include Phlex::Rails::Helpers::CSPMetaTag
  include Phlex::Rails::Helpers::CSRFMetaTags
  include Phlex::Rails::Helpers::FaviconLinkTag
  include Phlex::Rails::Helpers::PreloadLinkTag
  include Phlex::Rails::Helpers::StyleSheetLinkTag
  include Phlex::Rails::Helpers::ActionCableMetaTag
  include Phlex::Rails::Helpers::AutoDiscoveryLinkTag
  include Phlex::Rails::Helpers::JavaScriptIncludeTag
  include Phlex::Rails::Helpers::JavaScriptImportMapTags
  include Phlex::Rails::Helpers::JavaScriptImportModuleTag

  def self.included(klass)
    klass.extend(Phlex::Rails::Layout::Interface)
  end

  def template(&block)
    doctype
    html do
      head
      body(&block)
    end
  end

  private

  def after_template
    super
    @_buffer.gsub!('<!-- [SIDE_LOAD_STYLESHEETS] -->', capture { include_stylesheets })
  end

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

      include_javascripts type: :module, defer: true
    end
  end
end
