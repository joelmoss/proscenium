# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
module Proscenium
  module SideLoad
    DEFAULT_EXTENSIONS = %i[js css].freeze
    EXTENSIONS = %i[js css].freeze

    module_function

    # Side load the given asset `path`, by appending it to `Proscenium::Current.loaded`, which is a
    # Set of 'js' and 'css' asset paths. This is safe to call multiple times, as it uses Set's.
    # Meaning that side loading will never include duplicates.
    def append(path, *extensions)
      Proscenium::Current.loaded ||= EXTENSIONS.to_h { |e| [e, Set[]] }

      unless (unknown_extensions = extensions.difference(EXTENSIONS)).empty?
        raise ArgumentError, "unsupported extension(s): #{unknown_extensions.join(',')}"
      end

      loaded_types = []

      (extensions.empty? ? DEFAULT_EXTENSIONS : extensions).each do |ext|
        path_with_ext = "#{path}.#{ext}"
        ext = ext.to_sym

        next if Proscenium::Current.loaded[ext].include?(path_with_ext)
        next unless Rails.root.join(path_with_ext).exist?

        Proscenium::Current.loaded[ext] << path_with_ext
        loaded_types << ext
      end

      !loaded_types.empty? && Rails.logger.debug do
        "[Proscenium] Side loaded /#{path}.(#{loaded_types.join(',')})"
      end
    end

    module Monkey
      module TemplateRenderer
        private

        def render_template(view, template, layout_name, locals)
          layout = find_layout(layout_name, locals.keys, [formats.first])
          renderable = template.instance_variable_get(:@renderable)

          if template.is_a?(ActionView::Template::Renderable) &&
             renderable.class < ::ViewComponent::Base && renderable.class.format == :html
            # Side load controller rendered ViewComponent
            Proscenium::SideLoad.append "app/views/#{layout.virtual_path}" if layout
            Proscenium::SideLoad.append "app/views/#{renderable.virtual_path}"
          elsif template.respond_to?(:virtual_path) &&
                template.respond_to?(:type) && template.type == :html
            # Side load regular view template.
            Proscenium::SideLoad.append "app/views/#{layout.virtual_path}" if layout

            # Try side loading the variant template
            if template.respond_to?(:variant) && template.variant
              Proscenium::SideLoad.append "app/views/#{template.virtual_path}+#{template.variant}"
            end

            # The variant template may not exist (above), so we try the regular non-variant path.
            Proscenium::SideLoad.append "app/views/#{template.virtual_path}"
          end

          super
        end
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
