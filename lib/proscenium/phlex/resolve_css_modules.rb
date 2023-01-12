# frozen_string_literal: true

module Proscenium::Phlex::ResolveCssModules
  def _build_attributes(attributes, buffer:)
    attributes.tap do |attrs|
      attrs[:class] = resolve_css_modules(tokens(attrs[:class])) if attrs.key?(:class)
    end

    super(attributes, buffer: buffer)
  end

  private

  def resolve_css_modules(value)
    if value.include?('/') && Rails.application.config.proscenium.side_load
      value.split.map { |path| resolve_css_module_path path }.join ' '
    elsif value.include?('@')
      value.split.map do |cls|
        cls.starts_with?('@') ? cssm.class_names!(cls[1..]) : cls
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
      path = "/npm:@#{path}"
    elsif path.starts_with?('/')
      # Local path with leading slash
      path, name = path[1..].split('@')
    else
      # NPM module: mypackage/lib/button@default
      path, name = path.split('@')
    end

    path = "#{path}.module.css"

    Proscenium::SideLoad.append! path, :css
    Proscenium::Utils.class_names name, hash: Proscenium::Utils.digest(path[1..])
  end
end
