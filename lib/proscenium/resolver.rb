# frozen_string_literal: true

require 'active_support/current_attributes'

module Proscenium
  class Resolver < ActiveSupport::CurrentAttributes
    attribute :resolved unless Rails.env.production?
    mattr_accessor :resolved if Rails.env.production?

    # Resolve the given `path` to a fully qualified URL path.
    #
    # @param path [String] URL path, file system path, or bare specifier (ie. NPM package).
    # @return [String] URL path.
    def self.resolve(path)
      self.resolved ||= {}

      if path.start_with?('./', '../')
        raise ArgumentError, '`path` must be an absolute file system or URL path'
      end

      self.resolved[path] ||= if (gem = BundledGems.paths.find { |_, v| path.start_with? "#{v}/" })
                                path.sub(/^#{gem.last}/, "/node_modules/@rubygems/#{gem.first}")
                              elsif path.start_with?("#{Rails.root}/")
                                path.delete_prefix Rails.root.to_s
                              else
                                Builder.resolve path
                              end
    end
  end
end
