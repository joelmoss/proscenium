# frozen_string_literal: true

module Proscenium::CssModule
  module Monkey
    module PartialRenderer
      private

      def build_rendered_template(content, template)
        return super unless Proscenium.config.transform_class_names_in_rendered_templates

        path = Rails.root.join('app', 'views', template.virtual_path)
        super Transformer.new(path).transform_content!(content), template
      end
    end
  end
end
