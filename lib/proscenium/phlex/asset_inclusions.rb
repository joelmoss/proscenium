# frozen_string_literal: true

module Proscenium::Phlex::AssetInclusions
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::StyleSheetPath
  include Phlex::Rails::Helpers::JavaScriptPath

  def include_stylesheets
    comment { '[PROSCENIUM_STYLESHEETS]' }
  end

  def include_javascripts(defer_lazy_scripts: false)
    comment { '[PROSCENIUM_JAVASCRIPTS]' }
    !defer_lazy_scripts && include_lazy_javascripts
  end

  def include_lazy_javascripts
    comment { '[PROSCENIUM_LAZY_SCRIPTS]' }
  end

  def include_assets(defer_lazy_scripts: false)
    include_stylesheets
    include_javascripts(defer_lazy_scripts: defer_lazy_scripts)
  end

  def after_template
    super

    @_buffer.gsub! '<!-- [PROSCENIUM_STYLESHEETS] -->', capture_stylesheets!
    @_buffer.gsub! '<!-- [PROSCENIUM_JAVASCRIPTS] -->', capture_javascripts!

    if content_for?(:proscenium_lazy_scripts)
      flush
      @_buffer.gsub!('<!-- [PROSCENIUM_LAZY_SCRIPTS] -->', capture do
        content_for(:proscenium_lazy_scripts)
      end)
    else
      @_buffer.gsub! '<!-- [PROSCENIUM_LAZY_SCRIPTS] -->', ''
    end
  end

  private

  def capture_stylesheets!
    capture do
      Proscenium::Importer.each_stylesheet(delete: true) do |path, _path_options|
        link rel: 'stylesheet', href: stylesheet_path(path, extname: false)
      end
    end
  end

  def capture_javascripts! # rubocop:disable Metrics/*
    unless Rails.application.config.proscenium.code_splitting &&
           Proscenium::Importer.multiple_js_imported?
      return capture do
        Proscenium::Importer.each_javascript(delete: true) do |path, _|
          script(src: javascript_path(path, extname: false), type: :module)
        end
      end
    end

    imports = Proscenium::Importer.imported.dup
    paths_to_build = []
    Proscenium::Importer.each_javascript(delete: true) do |x, _|
      paths_to_build << x.delete_prefix('/')
    end

    result = Proscenium::Builder.build(paths_to_build.join(';'), base_url: helpers.request.base_url)

    # Remove the react components from the results, so they are not side loaded. Instead they
    # are lazy loaded by the component manager.

    capture do
      scripts = {}
      result.split(';').each do |x|
        inpath, outpath = x.split('::')
        inpath.prepend '/'
        outpath.delete_prefix! 'public'

        next unless imports.key?(inpath)

        if (import = imports[inpath]).delete(:lazy)
          scripts[inpath] = import.merge(outpath: outpath)
        else
          script(src: javascript_path(outpath, extname: false), type: :module)
        end
      end

      content_for :proscenium_lazy_scripts do
        script type: 'application/json', id: 'prosceniumLazyScripts' do
          unsafe_raw scripts.to_json
        end
      end
    end
  end
end
