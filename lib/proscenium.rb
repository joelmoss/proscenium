# frozen_string_literal: true

require 'active_support/dependencies/autoload'

module Proscenium
  extend ActiveSupport::Autoload

  autoload :Current
  autoload :Middleware
  autoload :SideLoad
  autoload :CssModule
  autoload :ViewComponent
  autoload :Phlex
  autoload :Helper
  autoload :LinkToHelper
  autoload :Precompile
  autoload :Esbuild

  def self.logger
    @logger ||= Rails.logger.tagged('Proscenium')
  end

  def self.reset_current_side_loaded
    Current.reset
    Current.loaded = SideLoad::EXTENSIONS.to_h { |e| [e, Set.new] }
  end

  module Utils
    module_function

    # @param value [#to_s] The value to create the digest from. This will usually be a `Pathname`.
    # @return [String] string digest of the given value.
    def digest(value)
      Digest::SHA1.hexdigest(value.to_s)[..7]
    end

    # Resolves the given CSS class names to CSS modules.
    #
    # @param names [String, Array]
    # @param hash: [String]
    # @returns [Array] of class names generated from the given CSS module `names` and `hash`.
    def class_names(*names, hash:)
      raise ArgumentError, "hash must be a non-blank string, but was #{hash.inspect}" if hash.blank?

      names.flatten.compact.map do |name|
        sname = name.to_s
        if sname.starts_with?('_')
          "_#{sname[1..].camelize(:lower)}#{hash}"
        else
          "#{sname.camelize(:lower)}#{hash}"
        end
      end
    end
  end
end

require 'proscenium/railtie'
