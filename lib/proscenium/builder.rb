# frozen_string_literal: true

require 'ffi'
require 'oj'

module Proscenium
  class Builder
    class CompileError < StandardError; end

    class Result < FFI::Struct
      layout :success, :bool,
             :response, :string
    end

    module Request
      extend FFI::Library
      ffi_lib Pathname.new(__dir__).join('ext/proscenium').to_s

      enum :environment, [:development, 1, :test, :production]

      attach_function :build_to_string, [
        :string,      # Path or entry point.
        :string,      # Base URL of the Rails app. eg. https://example.com
        :string,      # Path to import map, relative to root
        :string,      # ENV variables as a JSON string

        # Config
        :string,      # Rails application root
        :string,      # Proscenium gem root
        :environment, # Rails environment as a Symbol
        :bool,        # Code splitting enabled?
        :string,      # Engine names and paths as a JSON string
        :bool         # Debugging enabled?
      ], Result.by_value

      attach_function :build_to_path, [
        :string,      # Path or entry point. Multiple can be given by separating with a semi-colon
        :string,      # Base URL of the Rails app. eg. https://example.com
        :string,      # Path to import map, relative to root
        :string,      # ENV variables as a JSON string

        # Config
        :string,      # Rails application root
        :string,      # Proscenium gem root
        :environment, # Rails environment as a Symbol
        :bool,        # Code splitting enabled?
        :string,      # Engine names and paths as a JSON string
        :bool         # Debugging enabled?
      ], Result.by_value

      attach_function :resolve, [
        :string,      # path or entry point
        :string,      # path to import map, relative to root

        # Config
        :string,      # Rails application root
        :string,      # Proscenium gem root
        :environment, # Rails environment as a Symbol
        :bool         # debugging enabled?
      ], Result.by_value
    end

    class BuildError < StandardError
      attr_reader :error

      def initialize(error)
        @error = Oj.load(error, mode: :strict).deep_transform_keys(&:underscore)

        msg = @error['text']
        if (location = @error['location'])
          msg << " at #{location['file']}:#{location['line']}:#{location['column']}"
        end

        super(msg)
      end
    end

    class ResolveError < StandardError
      attr_reader :error_msg, :path

      def initialize(path, error_msg)
        super("Failed to resolve '#{path}' -- #{error_msg}")
      end
    end

    def self.build_to_path(path, root: nil, base_url: nil)
      new(root: root, base_url: base_url).build_to_path(path)
    end

    def self.build_to_string(path, root: nil, base_url: nil)
      new(root: root, base_url: base_url).build_to_string(path)
    end

    def self.resolve(path, root: nil)
      new(root: root).resolve(path)
    end

    def initialize(root: nil, base_url: nil)
      @root = root || Rails.root
      @base_url = base_url
    end

    def build_to_path(path)
      ActiveSupport::Notifications.instrument('build_to_path.proscenium',
                                              identifier: path,
                                              cached: Proscenium.cache.exist?(path)) do
        Proscenium.cache.fetch path do
          result = Request.build_to_path(path, @base_url, import_map, env_vars.to_json,
                                         @root.to_s,
                                         gem_root,
                                         Rails.env.to_sym,
                                         Proscenium.config.code_splitting,
                                         engines.to_json,
                                         Proscenium.config.debug)

          raise BuildError, result[:response] unless result[:success]

          result[:response]
        end
      end
    end

    def build_to_string(path)
      ActiveSupport::Notifications.instrument('build_to_string.proscenium', identifier: path) do
        result = Request.build_to_string(path, @base_url, import_map, env_vars.to_json,
                                         @root.to_s,
                                         gem_root,
                                         Rails.env.to_sym,
                                         Proscenium.config.code_splitting,
                                         engines.to_json,
                                         Proscenium.config.debug)

        raise BuildError, result[:response] unless result[:success]

        result[:response]
      end
    end

    def resolve(path)
      ActiveSupport::Notifications.instrument('resolve.proscenium', identifier: path) do
        result = Request.resolve(path, import_map, @root.to_s,
                                 gem_root,
                                 Rails.env.to_sym,
                                 Proscenium.config.debug)
        raise ResolveError.new(path, result[:response]) unless result[:success]

        result[:response]
      end
    end

    private

    # Build the ENV variables as determined by `Proscenium.config.env_vars` and
    # `Proscenium::DEFAULT_ENV_VARS` to pass to esbuild.
    def env_vars
      ENV['NODE_ENV'] = ENV.fetch('RAILS_ENV', nil)
      ENV.slice(*Proscenium.config.env_vars + Proscenium::DEFAULT_ENV_VARS)
    end

    def cache_query_string
      q = Proscenium.config.cache_query_string
      q ? "--cache-query-string #{q}" : nil
    end

    def engines
      Proscenium.config.engines.to_h { |e| [e.engine_name, e.root.to_s] }.tap do |x|
        x['proscenium/ui'] = Proscenium.ui_path.to_s
      end
    end

    def import_map
      return unless (path = Rails.root&.join('config'))

      if (json = path.join('import_map.json')).exist?
        return json.relative_path_from(@root).to_s
      end

      if (js = path.join('import_map.js')).exist?
        return js.relative_path_from(@root).to_s
      end

      nil
    end

    def gem_root
      Pathname.new(__dir__).join('..', '..').to_s
    end
  end
end
