# frozen_string_literal: true

module Proscenium
  module SideLoad::Helper
    def side_load_stylesheets
      return unless Proscenium::Current.loaded

      out = []
      Proscenium::Current.loaded[:css].delete_if do |path|
        out << stylesheet_link_tag(path, extname: false)
      end
      out.join("\n").html_safe
    end

    def side_load_javascripts(**options) # rubocop:disable Metrics/AbcSize
      return unless Proscenium::Current.loaded

      out = []
      paths = Proscenium::Current.loaded[:js]
      public_path = Rails.public_path.to_s

      if paths.size > 1
        paths_to_build = []
        paths.delete_if { |x| paths_to_build << x.delete_prefix('/') }

        result = Proscenium::Esbuild.build(paths_to_build.join(';'), root: Rails.root,
                                                                     base_url: request.base_url)
        result.split(';').each do |x|
          next if x.include?('public/assets/_chunks/') || x.end_with?('.map')

          out << javascript_include_tag(x.delete_prefix(public_path), extname: false, **options)
        end
      else
        paths.delete_if do |x|
          out << javascript_include_tag(x, extname: false, **options)
        end
      end

      out.join("\n").html_safe
    end
  end
end
