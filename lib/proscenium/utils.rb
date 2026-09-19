# frozen_string_literal: true

module Proscenium
  module Utils
    module_function

    # Returns a short digest for the given `value`, intended for CSS module class name suffixes.
    #
    # @param value [#to_s] The value to create the digest from. This will usually be the absolute
    #   file system file path.
    # @return [String] digest of the given value.
    def css_module_digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
    end

    # Returns the readable part of a CSS module class name: the given path, made safe to use in a
    # class name.
    #
    # This is a port of `CssLocalAppendice` in esbuild-internal, which builds the class names in the
    # stylesheet. The two must agree byte for byte or the style silently does not apply, so change
    # them together. The rules: drop the file extension, turn `/`, `\` and `.` into `-`, turn any
    # other character outside `A-Z a-z 0-9 - _` into `_`, and start with `_` if the result would
    # start with a digit.
    #
    # @param path [#to_s] path of the CSS module file, relative to the app root.
    # @return [String]
    def css_module_suffix(path)
      path.to_s
          .sub(%r{\.[^./]*\z}, '')
          .gsub(%r{[/\\.]}, '-')
          .gsub(/[^A-Za-z0-9_-]/, '_')
          .sub(/\A(?=\d)/, '_')
    end

    # Merges the given array of attribute `name`'s into the `kw_arguments`. A bang attribute is one
    # that ends with an exclamation mark or - in Ruby parlance - a "bang", and has a boolean value.
    # Modifies the given `kw_attributes`, and only attribute names in `allowed` will be merged.
    #
    # @param names [Array(Symbol)] of argument names
    # @param kw_attributes [Hash] attributes to be merged with
    # @param allowed [Array(Symbol)] attribute names allowed to be merged as bang attributes
    #
    # Example:
    #
    #   def tab(name, *args, href:, **attributes)
    #     Hue::Utils.merge_bang_attributes!(args, attributes, [:current])
    #   end
    #
    # Allowing you to use either of the following API's:
    #
    #   tab 'Tab 1', required: true
    #   tab 'Tab 1', :required!
    #
    def merge_bang_attributes!(names, kw_attributes, allowed)
      allowed.each do |name|
        sym_name = name.to_sym
        bang_name = :"#{sym_name}!"

        next unless names.include?(bang_name)

        names.delete(bang_name)

        # Keyword arguments should override the bang.
        kw_attributes[sym_name] = true unless kw_attributes.key?(sym_name)
      end
    end
  end
end
