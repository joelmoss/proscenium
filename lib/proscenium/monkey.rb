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

    # A collection renders each item with `Template#render`, so never reaches
    # `PartialRenderer#render_partial_template`. Hooked above the collection cache, which skips
    # rendering entirely on a full hit. A mixed collection has no single template, and is not side
    # loaded.
    module CollectionRenderer
      private

      # `args` is `path, template, layout, block`. `collection` is ActionView's CollectionIterator,
      # which has `length` but no `empty?`.
      def render_collection(collection, view, *args)
        _path, template, layout, = args
        return super unless collection.length.positive? && SideLoad.sideloadable?(view, template)

        SideLoad.sideload_templates(view, [layout, template]) { super }
      end
    end
  end
end
