# frozen_string_literal: true

module Proscenium
  module SideLoad::Helper
    def side_load_stylesheets
      return unless Proscenium::Current.loaded

      out = []
      Proscenium::Current.loaded[:css].delete_if do |path|
        out << stylesheet_link_tag(path)
      end
      out.join("\n").html_safe
    end

    def side_load_javascripts(**options)
      return unless Proscenium::Current.loaded

      out = []
      Proscenium::Current.loaded[:js].delete_if do |path|
        out << javascript_include_tag(path, options)
      end
      out.join("\n").html_safe
    end
  end
end
