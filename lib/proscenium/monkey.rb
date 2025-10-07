# frozen_string_literal: true

module Proscenium
  module Monkey
    module TemplateRenderer
      private

      def render_template(view, template, layout_name, locals)
        result = super
        return result if !view.controller || !Proscenium.config.side_load

        to_sideload = if template.respond_to?(:identifier) &&
                         template.respond_to?(:type) && template.type == :html
                        template
                      end
        if to_sideload && view.controller.respond_to?(:sideload_assets_options)
          options = view.controller.sideload_assets_options
          layout = find_layout(layout_name, locals.keys, [formats.first])
          sideload_template_assets layout, view.controller, options if layout
          sideload_template_assets to_sideload, view.controller, options
        end

        result
      end

      def sideload_template_assets(tpl, controller, options)
        return unless (tpl_path = Pathname.new(tpl.identifier)).file?

        options = {} if options.nil?
        options = { js: options, css: options } unless options.is_a?(Hash)

        if tpl.instance_variable_defined?(:@sideload_assets_options)
          tpl_options = tpl.instance_variable_get(:@sideload_assets_options)
          options = case tpl_options
                    when Hash then options.deep_merge(tpl_options)
                    else
                      { js: tpl_options, css: tpl_options }
                    end
        end

        %i[css js].each do |k|
          options[k] = controller.instance_eval(&options[k]) if options[k].is_a?(Proc)
        end

        Importer.sideload tpl_path, **options
      end
    end

    module PartialRenderer
      private

      def render_partial_template(view, locals, template, layout, block)
        result = super

        return result if !view.controller || !Proscenium.config.side_load

        if template.respond_to?(:identifier) &&
           template.respond_to?(:type) && template.type == :html &&
           view.controller.respond_to?(:sideload_assets_options)
          options = view.controller.sideload_assets_options
          sideload_template_assets layout, options if layout
          sideload_template_assets template, options
        end

        result
      end

      def sideload_template_assets(tpl, options)
        return unless (tpl_path = Pathname.new(tpl.identifier)).file?

        options = {} if options.nil?
        options = { js: options, css: options } unless options.is_a?(Hash)

        if tpl.instance_variable_defined?(:@sideload_assets_options)
          tpl_options = tpl.instance_variable_get(:@sideload_assets_options)
          options = if tpl_options.is_a?(Hash)
                      options.deep_merge tpl_options
                    else
                      { js: tpl_options, css: tpl_options }
                    end
        end

        %i[css js].each do |k|
          options[k] = controller.instance_eval(&options[k]) if options[k].is_a?(Proc)
        end

        Importer.sideload tpl_path, **options
      end
    end
  end
end
