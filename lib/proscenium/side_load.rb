# frozen_string_literal: true

module Proscenium
  class SideLoad
    extend ActiveSupport::Autoload

    NotIncludedError = Class.new(StandardError)

    autoload :Monkey

    class << self
      def sideload_inheritance_chain(obj)
        return if !Proscenium.config.side_load || (obj.respond_to?(:sideload?) && !obj.sideload?)

        klass = obj.class
        while klass.respond_to?(:source_path) && klass.source_path && !klass.abstract_class
          klass.respond_to?(:sideload) ? klass.sideload : Importer.sideload(klass.source_path)
          klass = klass.superclass
        end
      end
    end
  end
end
