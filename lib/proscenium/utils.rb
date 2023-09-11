# frozen_string_literal: true

module Proscenium
  module Utils
    module_function

    # @param value [#to_s] The value to create the digest from. This will usually be a `Pathname`.
    # @return [String] digest of the given value.
    def digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
    end
  end
end
