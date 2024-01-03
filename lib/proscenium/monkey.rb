# frozen_string_literal: true

module Proscenium
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  module Monkey
    module TemplateRenderer
      private

      def render_template(view, template, layout_name, locals) # rubocop:disable Metrics/*
        result = super
        return result if !view.controller || !Proscenium.config.side_load

        renderable = template.instance_variable_get(:@renderable)

        to_sideload = if Object.const_defined?(:ViewComponent) &&
                         template.is_a?(ActionView::Template::Renderable) &&
                         renderable.class < ::ViewComponent::Base &&
                         renderable.class.format == :html
                        renderable
                      elsif template.respond_to?(:virtual_path) &&
                            template.respond_to?(:type) && template.type == :html
                        template
                      end
        if to_sideload
          options = view.controller.sideload_assets_options
          layout = find_layout(layout_name, locals.keys, [formats.first])
          sideload_template_assets layout, view.controller, options if layout
          sideload_template_assets to_sideload, view.controller, options
        end

        result
      end

      def sideload_template_assets(tpl, controller, options)
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

        Importer.sideload "app/views/#{tpl.virtual_path}", **options
      end
    end

    module PartialRenderer
      private

      def render_partial_template(view, locals, template, layout, block)
        result = super

        return result if !view.controller || !Proscenium.config.side_load

        if template.respond_to?(:virtual_path) &&
           template.respond_to?(:type) && template.type == :html
          options = view.controller.sideload_assets_options
          sideload_template_assets layout, options if layout
          sideload_template_assets template, options
        end

        result
      end

      def sideload_template_assets(tpl, options)
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

        Importer.sideload "app/views/#{tpl.virtual_path}", **options
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
