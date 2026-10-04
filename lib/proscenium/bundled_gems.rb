# frozen_string_literal: true

require 'json'
require_relative 'error'

module Proscenium
  # The one reader of the bundle, for the engine and the `proscenium` CLI alike, so the two never
  # disagree about which gems exist or which take part in JavaScript dependency installation
  # (#154). It must not load ActiveSupport or anything else the CLI may not.
  module BundledGems
    # proscenium.json is unreadable or not in the documented shape.
    class ConfigError < Proscenium::Error; end

    CONFIG = 'proscenium.json'

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
    #
    # The longest root wins, which is Go's rule in `GemFromFsPath`, so a file under a gem nested in
    # another gem's tree gets one URL from both sides. `max_by` keeps the first of equal roots, and
    # `paths` is sorted by name, so a tie goes to the first name, as it does in Go.
    def virtual_path(abs_path)
      name, root = paths.select { |_, v| abs_path.start_with? "#{v}/" }.max_by { |_, v| v.length }
      name && "@rubygems/#{name}#{abs_path.delete_prefix(root)}"
    end

    # Every installed gem but Bundler, sorted by name: the specs of the groups Bundler loaded.
    def installed_specs = Bundler.load.specs.reject { it.name == 'bundler' }.sort_by(&:name)

    # The names in Gemfile.lock, installed or not, or nil without a lockfile. A gem in a group
    # BUNDLE_WITHOUT excludes, or locked for another platform, is here but not installed.
    def locked_names
      locked = Bundler.locked_gems
      locked && locked.specs.map(&:name).uniq.sort
    end

    # Locked gems that are not installed: their committed contexts are trusted as they are (the
    # production rule).
    def excluded_names(specs = installed_specs)
      (locked_names || []) - specs.map(&:name)
    end

    # `gemOverrides` from the app's proscenium.json: gem name => true or false, or {} without one.
    def overrides(root)
      path = File.join(root, CONFIG)
      return {} unless File.exist?(path)

      config = JSON.parse(File.read(path))
      raise ConfigError, "#{CONFIG} must be a JSON object" unless config.is_a?(Hash)
      raise ConfigError, "#{CONFIG} must have \"schema\": 1" unless config['schema'] == 1

      (config['gemOverrides'] || {}).to_h do |gem, settings|
        participate = settings.is_a?(Hash) ? settings['participate'] : nil
        unless [true, false].include?(participate)
          raise ConfigError, "#{CONFIG}: gemOverrides.#{gem}.participate must be true or false"
        end

        [gem, participate]
      end
    rescue JSON::ParserError => e
      raise ConfigError, "#{CONFIG} is not valid JSON (#{e.message.lines.first.strip})"
    end

    # Whether the gem's author opted it in, with gemspec metadata.
    def opted_in?(spec) = spec.metadata['proscenium.dependencies'] == 'true'

    # The gem's `proscenium.frontend_root`, relative to the gem: '' for its root, nil if it names a
    # place outside the gem.
    def frontend_root(spec)
      relative = spec.metadata['proscenium.frontend_root'].to_s.delete_prefix('./').chomp('/')
      return nil if relative.start_with?('/') || relative.split('/').include?('..')

      relative
    end

    # The installed directory holding the gem's package.json, or nil if its frontend root is
    # outside the gem.
    def manifest_root(spec)
      relative = frontend_root(spec)
      return nil unless relative

      relative.empty? ? spec.full_gem_path : File.join(spec.full_gem_path, relative)
    end

    # The participating installed specs, by name: opted in by their author or the app, and not
    # opted out by the app.
    def participating(specs = installed_specs, overrides: {})
      specs.select { |spec| overrides.fetch(spec.name) { opted_in?(spec) } }.to_h { [it.name, it] }
    end

    # Installed gems that ship a root package.json but do not participate, for `inspect`.
    def unparticipating_with_manifest(specs = installed_specs, overrides: {})
      chosen = participating(specs, overrides:)
      specs.reject { chosen.key?(it.name) }
           .select { File.exist?(File.join(it.full_gem_path, 'package.json')) }
           .map(&:name)
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
