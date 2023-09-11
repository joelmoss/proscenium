# frozen_string_literal: true

module Proscenium
  module CssModule::Path
    # Returns the path to the CSS module file for this class, where the file is located alongside
    # the class file, and has the same name as the class file, but with a `.module.css` extension.
    #
    # If the CSS module file does not exist, it's ancestry is checked, returning the first that
    # exists. Then finally `nil` is returned if never found.
    #
    # @return [Pathname]
    def css_module_path
      return @css_module_path if instance_variable_defined?(:@css_module_path)

      path = source_path.sub_ext('.module.css')
      @css_module_path = path.exist? ? path : nil

      unless @css_module_path
        klass = superclass

        while klass.respond_to?(:css_module_path) && !klass.abstract_class
          break if (@css_module_path = klass.css_module_path)

          klass = klass.superclass
        end
      end

      @css_module_path
    end
  end
end
