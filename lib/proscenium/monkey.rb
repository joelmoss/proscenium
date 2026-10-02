# frozen_string_literal: true

module Proscenium
  module Monkey
    # A template ActionView pushes onto `@current_template` is not the body of a partial rendered
    # with a block, so `Helper#sideload_assets` must not see that partial while one renders. Rails
    # caches template objects, so the pushed template can be the very one that rendered the partial.
    #
    # Overrides ActionView's private `ActionView::Base#_run(method, template, locals, buffer,
    # add_to_stack: true, ...)`, unchanged from Rails 7.2 to 8.1. `@proscenium_block_partial` is
    # set by `Helper#proscenium_render_block_partial`. Every template render runs through here, so
    # arguments are forwarded with `...`, which allocates nothing. Reading `add_to_stack` does
    # allocate, so it is only read while a block partial is rendering.
    module Base
      def _run(...)
        return super unless @proscenium_block_partial && proscenium_pushes_template?(...)

        owner = @proscenium_block_partial
        @proscenium_block_partial = nil
        super
      ensure
        @proscenium_block_partial = owner if owner
      end

      private

      def proscenium_pushes_template?(*, add_to_stack: true, **) = add_to_stack
    end

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

        SideLoad.sideload_templates(view, [layout, template]) do
          # A view rendered before Proscenium::Helper is included cannot call `sideload_assets`.
          if block && view.respond_to?(:proscenium_render_block_partial)
            view.proscenium_render_block_partial(template, block) do |wrapped|
              super(view, locals, template, layout, wrapped)
            end
          else
            super
          end
        end
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
