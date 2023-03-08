# frozen_string_literal: true

module Proscenium::Phlex::ResolveCssModules
  extend ActiveSupport::Concern

  class_methods do
    attr_accessor :side_load_cache
  end

  def before_template
    self.class.side_load_cache ||= Set.new
    super
  end

  def process_attributes(**attributes)
    attributes[:class] = resolve_css_modules(tokens(attributes[:class])) if attributes.key?(:class)
    attributes
  end

  def after_template
    super

    self.class.side_load_cache&.each do |path|
      Proscenium::SideLoad.append! path, :css
    end
  end

  private

  # Resolves the given HTML class name or path as a CSS module.
  #
  # @param value [String] HTML class name or path to resolve.
  def resolve_css_modules(value) # rubocop:disable Metrics/AbcSize
    if value.include?('/') && Rails.application.config.proscenium.side_load
      value.split.map { |path| resolve_css_module_path path }.join ' '
    elsif value.include?('@')
      value.split.map do |cls|
        if cls.starts_with?('@')
          classes = cssm.class_names!(cls[1..])
          cssm.side_loaded? && self.class.side_load_cache.merge(cssm.side_loaded_paths)
          classes
        else
          cls
        end
      end.join ' '
    else
      value
    end
  end

  # @experimental
  #
  # Resove the given CSS module path, where path is something like `path/to/my/css@name`. It
  # supports local and NPM packages, but does not go through the proscenium pipeline, so ignores
  # importmap and any of the Node and Proscenium module resolution.
  def resolve_css_module_path(path)
    if path.starts_with?('@')
      # Scoped NPM module: @scoped/package/lib/button@default
      _, path, name = path.split('@')
      path = "npm:@#{path}"
    elsif path.starts_with?('/')
      # Local path with leading slash
      path, name = path[1..].split('@')
    else
      # NPM module: mypackage/lib/button@default
      path, name = path.split('@')
    end

    self.class.side_load_cache << (path = "#{path}.module.css")
    Proscenium::Utils.class_names name, hash: Proscenium::Utils.digest(path)
  end
end
