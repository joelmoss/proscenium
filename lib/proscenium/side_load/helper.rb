# frozen_string_literal: true

module Proscenium
  module SideLoad::Helper
    def side_load_stylesheets(**options)
      return unless Proscenium::Current.loaded

      out = []
      Proscenium::Current.loaded[:css].delete_if do |path|
        out << stylesheet_link_tag(path, extname: false, **options)
      end
      out.join("\n").html_safe
    end

    def side_load_javascripts(**options) # rubocop:disable Metrics/AbcSize
      return unless Proscenium::Current.loaded

      out = []
      paths = Proscenium::Current.loaded[:js]

      if Rails.application.config.proscenium.code_splitting && paths.size > 1
        public_path = Rails.public_path.to_s
        paths_to_build = []
        paths.delete_if { |x| paths_to_build << x.delete_prefix('/') }

        result = Proscenium::Builder.build(paths_to_build.join(';'), base_url: request.base_url)

        # Remove the react components from the results, so they are not side loaded. Instead they
        # are lazy loaded by the component manager.

        scripts = {}
        result.split(';').each do |path|
          path.delete_prefix! public_path

          next if path.start_with?('/assets/_asset_chunks/') || path.end_with?('.map')

          if path.start_with?('/assets/app/components/')
            match = path.match(%r{/assets(/app/components/.+/component)\$[a-z0-9]{8}\$\.js$}i)[1]
            scripts[match] = path
          else
            out << javascript_include_tag(path, extname: false, **options)
          end
        end

        out << javascript_tag("window.prosceniumComponents = #{scripts.to_json}")
      else
        paths.delete_if do |path|
          out << javascript_include_tag(path, extname: false, **options)
        end
      end

      out.join("\n").html_safe
    end
  end
end
