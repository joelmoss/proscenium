# frozen_string_literal: true

require 'prism'
require 'require-hooks/setup'

module Proscenium
  module CssModule
    class Rewriter
      def self.init(include: [], exclude: [])
        RequireHooks.source_transform(
          patterns: include,
          exclude_patterns: exclude
        ) do |path, source|
          source ||= File.read(path)
          Processor.call(source)
        end
      end

      class Processor < Prism::Visitor
        def self.call(source)
          visitor = new
          visitor.visit(Prism.parse(source).value)

          buffer = source.dup
          annotations = visitor.annotations
          annotations.sort_by!(&:first)

          annotations.reverse_each do |offset, action|
            case action
            when :start
              buffer.insert(offset, 'class_names(*')
            when :end
              buffer.insert(offset, ')')
            else
              raise 'Invalid annotation'
            end
          end

          buffer
        end

        def initialize
          @annotations = []
        end

        PREFIX = '@'

        attr_reader :annotations

        def visit_assoc_node(node)
          # Skip if the key is not a symbol or string
          return if %i[symbol_node string_node].exclude?(node.key.type)

          return if node.key.type == :symbol_node && node.key.value != 'class'
          return if node.key.type == :string_node && node.key.content != 'class'

          value = node.value
          type = value.type

          if (type == :symbol_node && value.value.start_with?(PREFIX)) ||
             (type == :array_node && value.elements.any? { |it| it.value.start_with?(PREFIX) })
            build_annotation value
          end
        end

        def build_annotation(value)
          location = value.location

          @annotations <<
            [location.start_character_offset, :start] <<
            [location.end_character_offset, :end]
        end
      end
    end
  end
end
