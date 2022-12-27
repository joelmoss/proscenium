# frozen_string_literal: true

class Proscenium::SideLoad
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  module Monkey
    module TemplateRenderer
      private

      def render_template(view, template, layout_name, locals)
        layout = find_layout(layout_name, locals.keys, [formats.first])
        renderable = template.instance_variable_get(:@renderable)

        if Object.const_defined?(:ViewComponent) &&
           template.is_a?(ActionView::Template::Renderable) &&
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

    module PartialRenderer
      private

      def build_rendered_template(content, template)
        path = Rails.root.join('app', 'views', template.virtual_path)
        cssm = Proscenium::CssModule::Resolver.new(path)
        super cssm.compile_class_names(content), template
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
