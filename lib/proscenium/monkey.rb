# frozen_string_literal: true

module Proscenium
  module Monkey
    module TemplateRenderer
      private

      def render_template(view, template, layout_name, locals)
        return super unless SideLoad.sideloadable?(view, template)

        layout = find_layout(layout_name, locals.keys, [formats.first])
        SideLoad.sideload_templates(view, [layout, template]) { super }
      end
    end

    module PartialRenderer
      private

      def render_partial_template(view, locals, template, layout, block)
        return super unless SideLoad.sideloadable?(view, template)

        SideLoad.sideload_templates(view, [layout, template]) { super }
      end
    end
  end
end
