# frozen_string_literal: true

module Proscenium
  module Utils
    module_function

    # @param value [#to_s] The value to create the digest from. This will usually be a `Pathname`.
    # @return [String] digest of the given value.
    def digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
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
