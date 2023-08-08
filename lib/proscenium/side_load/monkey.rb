# frozen_string_literal: true

class Proscenium::SideLoad
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  module Monkey
    module TemplateRenderer
      private

      def render_template(view, template, layout_name, locals)
        return super unless Proscenium.config.side_load

        layout = find_layout(layout_name, locals.keys, [formats.first])
        renderable = template.instance_variable_get(:@renderable)

        if Object.const_defined?(:ViewComponent) &&
           template.is_a?(ActionView::Template::Renderable) &&
           renderable.class < ::ViewComponent::Base && renderable.class.format == :html
          # Side load controller rendered ViewComponent
          Proscenium::Importer.sideload "app/views/#{layout.virtual_path}" if layout
          Proscenium::Importer.sideload "app/views/#{renderable.virtual_path}"
        elsif template.respond_to?(:virtual_path) &&
              template.respond_to?(:type) && template.type == :html
          Proscenium::Importer.sideload "app/views/#{layout.virtual_path}" if layout

          # Try side loading the variant template
          if template.respond_to?(:variant) && template.variant
            Proscenium::Importer.sideload "app/views/#{template.virtual_path}+#{template.variant}"
          end

          Proscenium::Importer.sideload "app/views/#{template.virtual_path}"
        end

        super
      end
    end

    module PartialRenderer
      private

      def render_partial_template(view, locals, template, layout, block)
        if Proscenium.config.side_load && template.respond_to?(:virtual_path) &&
           template.respond_to?(:type) && template.type == :html
          Proscenium::Importer.sideload "app/views/#{layout.virtual_path}" if layout
          Proscenium::Importer.sideload "app/views/#{template.virtual_path}"
        end

        super
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
