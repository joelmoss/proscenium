# frozen_string_literal: true

module Proscenium
  module SideLoadHelper
    def side_load_stylesheets
      return unless Proscenium::Current.loaded

      stylesheet_link_tag(*Proscenium::Current.loaded[:css])
    end

    def side_load_javascripts(**options)
      return unless Proscenium::Current.loaded

      javascript_include_tag(*Proscenium::Current.loaded[:js], options)
    end
  end
end
