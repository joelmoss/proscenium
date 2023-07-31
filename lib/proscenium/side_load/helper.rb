# frozen_string_literal: true

module Proscenium
  module SideLoad::Helper
    def side_load_stylesheets(**options)
      out = []
      Proscenium::Importer.each_stylesheet(delete: true) do |path, _path_options|
        out << stylesheet_link_tag(path, extname: false, **options)
      end
      out.join("\n").html_safe
    end

    def side_load_javascripts(**options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      out = []

      if Rails.application.config.proscenium.code_splitting &&
         Proscenium::Importer.multiple_js_imported?
        imports = Proscenium::Importer.imported.dup

        paths_to_build = []
        Proscenium::Importer.each_javascript(delete: true) do |x, _|
          paths_to_build << x.delete_prefix('/')
        end

        result = Proscenium::Builder.build(paths_to_build.join(';'), base_url: request.base_url)

        # Remove the react components from the results, so they are not side loaded. Instead they
        # are lazy loaded by the component manager.

        scripts = {}
        result.split(';').each do |x|
          inpath, outpath = x.split('::')
          inpath.prepend '/'
          outpath.delete_prefix! 'public'

          next unless imports.key?(inpath)

          import = imports[inpath]
          if import[:lazy]
            import.delete :lazy
            scripts[inpath] = import.merge(outpath: outpath)
          else
            out << javascript_include_tag(outpath, extname: false, **options)
          end
        end

        out << javascript_tag("window.prosceniumComponents = #{scripts.to_json}")
      else
        Proscenium::Importer.each_javascript(delete: true) do |path, _path_options|
          out << javascript_include_tag(path, extname: false, **options)
        end
      end

      out.join("\n").html_safe
    end
  end
end
