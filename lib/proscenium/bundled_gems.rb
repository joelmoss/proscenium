# frozen_string_literal: true

module Proscenium
  module BundledGems
    module_function

    def paths
      specs = Bundler.load.specs.reject { |s| s.name == 'bundler' }.sort_by(&:name)

      raise 'No gems in your Gemfile' if specs.empty?

      bundle = {}
      specs.each do |s|
        bundle[s.name] = s.full_gem_path
      end
      bundle
    end

    # def pathname_for(name)
    #   spec = Bundler.load.specs.find { |s| s.name == name }

    #   raise "Gem `#{name}` not found in your Gemfile" unless spec

    #   Pathname spec.full_gem_path
    # end
  end
end
