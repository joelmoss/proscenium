# frozen_string_literal: true

module Proscenium
  class Bundle
    def self.paths
      new.paths
    end

    def paths
      specs = Bundler.load.specs.reject { |s| s.name == 'bundler' }.sort_by(&:name)

      raise 'No gems in the Gemfile' if specs.empty?

      bundle = {}
      specs.each do |s|
        bundle[s.name] = s.full_gem_path
      end
      bundle
    end
  end
end
