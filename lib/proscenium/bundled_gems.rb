# frozen_string_literal: true

module Proscenium
  module BundledGems
    module_function

    def paths
      @paths ||= begin
        specs = Bundler.load.specs.reject { |s| s.name == 'bundler' }.sort_by(&:name)

        raise 'No gems in your Gemfile' if specs.empty?

        bundle = {}
        specs.each do |s|
          bundle[s.name] = if s.name == 'proscenium'
                             Pathname(s.full_gem_path).join('lib/proscenium').to_s
                           else
                             s.full_gem_path
                           end
        end
        bundle
      end
    end

    def pathname_for(name)
      (path = paths[name]) ? Pathname(path) : nil
    end

    def pathname_for!(name)
      unless (path = pathname_for(name))
        raise "Gem `#{name}` not found in your Gemfile"
      end

      path
    end
  end
end
