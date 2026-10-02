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

    # The `@rubygems/` form of an absolute path inside a bundled gem, or nil when it is in none.
    # A plain prefix match: a gem path is text, not a pattern, and may hold `+` or `(`.
    def virtual_path(abs_path)
      name, root = paths.find { |_, v| abs_path.start_with? "#{v}/" }
      name && "@rubygems/#{name}#{abs_path.delete_prefix(root)}"
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
