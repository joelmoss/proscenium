# frozen_string_literal: true

require 'ffi'
require 'oj'

module Proscenium
  class Builder
    class CompileError < StandardError; end

    ENVIRONMENTS = { development: 1, test: 2, production: 3 }.freeze

    class Result < FFI::Struct
      layout :success, :bool,
             :response, :string
    end

    module Request
      extend FFI::Library
      ffi_lib Pathname.new(__dir__).join('ext/proscenium').to_s

      enum :environment, [:development, 1, :test, :production]

      attach_function :build_to_string, [
        :string, # Path or entry point.
        :pointer # Config as JSON.
      ], Result.by_value

      attach_function :build_to_path, [
        :string, # Path or entry point. Multiple can be given by separating with a semi-colon
        :pointer # Config as JSON.
      ], Result.by_value

      attach_function :resolve, [
        :string, # path or entry point
        :pointer # Config as JSON.
      ], Result.by_value

      attach_function :reset_config, [], :void
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

    def self.build_to_path(path, root: nil)
      new(root:).build_to_path(path)
    end

    def self.build_to_string(path, root: nil)
      new(root:).build_to_string(path)
    end

    def self.resolve(path, root: nil)
      new(root:).resolve(path)
    end

    # Intended for tests only.
    def self.reset_config!
      Request.reset_config
    end

    def initialize(root: nil)
      @request_config = FFI::MemoryPointer.from_string({
        RootPath: (root || Rails.root).to_s,
        GemPath: gem_root,
        Environment: ENVIRONMENTS.fetch(Rails.env.to_sym, 2),
        Engines: engines,
        EnvVars: env_vars,
        CodeSplitting: Proscenium.config.code_splitting,
        Bundle: Proscenium.config.bundle,
        Debug: Proscenium.config.debug
      }.to_json)
    end

    def build_to_path(path)
      ActiveSupport::Notifications.instrument('build_to_path.proscenium',
                                              identifier: path,
                                              cached: Proscenium.cache.exist?(path)) do
        Proscenium.cache.fetch path do
          result = Request.build_to_path(path, @request_config)

          raise BuildError, result[:response] unless result[:success]

          result[:response]
        end
      end
    end

    def build_to_string(path)
      ActiveSupport::Notifications.instrument('build_to_string.proscenium', identifier: path) do
        result = Request.build_to_string(path, @request_config)

        raise BuildError, result[:response] unless result[:success]

        result[:response]
      end
    end

    def resolve(path)
      ActiveSupport::Notifications.instrument('resolve.proscenium', identifier: path) do
        result = Request.resolve(path, @request_config)

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

    # def import_map_path
    #   return unless (path = Rails.root&.join('config'))

    #   if (json = path.join('import_map.json')).exist?
    #     return json.relative_path_from(@root).to_s
    #   end

    #   if (js = path.join('import_map.js')).exist?
    #     return js.relative_path_from(@root).to_s
    #   end

    #   nil
    # end

    def gem_root
      Pathname.new(__dir__).join('..', '..').to_s
    end
  end
end
