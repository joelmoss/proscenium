# frozen_string_literal: true

module Proscenium
  class SideLoad
    class << self
      # Side loads the class, and its super classes that respond to `.source_path`.
      #
      # Assign the `abstract_class` class variable to any abstract class, and it will not be side
      # loaded. Additionally, if the class responds to `#sideload?`, and it returns false, it will
      # not be side loaded.
      #
      # If the class responds to `.sideload`, it will be called instead of the regular side loading.
      # You can use this to customise what is side loaded.
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
