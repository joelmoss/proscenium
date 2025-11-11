# frozen_string_literal: true

require 'active_support/current_attributes'

module Proscenium
  class Resolver < ActiveSupport::CurrentAttributes
    attribute :resolved unless Rails.env.production?
    mattr_accessor :resolved if Rails.env.production?

    # Resolve the given `path` to a fully qualified URL path.
    #
    # TODO: cache this across requests in production.
    #
    # @param path [String] URL path, file system path, or bare specifier (ie. NPM package).
    # @param as_array [Boolean] whether or not to return the manifest path, non-manifest path, and
    #   absolute file system path as an array. Only returns the resolved path if false (default).
    # @return [String, Array<String>]
    def self.resolve(path, as_array: false)
      self.resolved ||= {}

      if path.start_with?('./', '../')
        raise ArgumentError, '`path` must be an absolute file system or URL path'
      end

      self.resolved[path] ||= if (gem = BundledGems.paths.find { |_, v| path.start_with? "#{v}/" })
                                vpath = path.sub(/^#{gem.last}/, "@rubygems/#{gem.first}")
                                [Proscenium::Manifest[vpath], "/node_modules/#{vpath}", path]
                              elsif path.start_with?("#{Rails.root}/")
                                vpath = path.delete_prefix(Rails.root.to_s)
                                [Proscenium::Manifest[vpath], vpath, path]
                              else
                                [Proscenium::Manifest[path], *Builder.resolve(path)]
                              end

      as_array ? self.resolved[path] : self.resolved[path][0] || self.resolved[path][1]
    end
  end
end
