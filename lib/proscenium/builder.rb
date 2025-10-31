# frozen_string_literal: true

require 'ffi'

module Proscenium
  class Builder
    ENVIRONMENTS = { development: 1, test: 2, production: 3 }.freeze

    class Result < FFI::Struct
      layout :success, :bool,
             :response, :string,
             :content_hash, :string
    end

    class CompileResult < FFI::Struct
      layout :success, :bool,
             :messages, :string
    end

    module Request
      extend FFI::Library

      ffi_lib Pathname.new(__dir__).join('ext/proscenium').to_s

      enum :environment, [:development, 1, :test, :production]

      attach_function :build_to_string, [
        :string, # Path or entry point.
        :string, # cache_query_string.
        :pointer # Config as JSON.
      ], Result.by_value

      attach_function :resolve, [
        :string, # path or entry point
        :pointer # Config as JSON.
      ], Result.by_value

      attach_function :compile, [
        :pointer # Config as JSON.
      ], CompileResult.by_value

      attach_function :reset_config, [], :void
    end

    class BuildError < Error
      attr_reader :error, :path

      def initialize(path, error)
        @path = path
        @error = JSON.parse(error, strict: true)

        msg = @error['Text']
        msg << ' - ' << @error['Detail'] if @error['Detail'].is_a?(String)
        if (location = @error['Location'])
          msg << " at #{location['File']}:#{location['Line']}:#{location['Column']}"
        end

        super("Failed to build #{path} - #{msg}")
      end
    end

    class ResolveError < Error
      attr_reader :path

      def initialize(path, msg)
        @path = path
        super("Failed to resolve #{path} - #{msg}")
      end
    end

    def self.build_to_string(path, cache_query_string: '', root: nil)
      new(root:).build_to_string(path, cache_query_string:)
    end

    def self.resolve(path, root: nil)
      new(root:).resolve(path)
    end

    def self.compile(root: nil)
      new(root:).compile
    end

    # Intended for tests only.
    def self.reset_config!
      Request.reset_config
    end

    def initialize(root: nil)
      @request_config = FFI::MemoryPointer.from_string({
        RootPath: (root || Rails.root).to_s,
        OutputDir: "public#{Proscenium.config.output_dir}",
        GemPath: gem_root,
        Environment: ENVIRONMENTS.fetch(Rails.env.to_sym, 2),
        EnvVars: env_vars,
        CodeSplitting: Proscenium.config.code_splitting,
        RubyGems: Proscenium::BundledGems.paths,
        Bundle: Proscenium.config.bundle,
        Aliases: Proscenium.config.aliases,
        Precompile: Proscenium.config.precompile,
        QueryString: Proscenium.config.cache_query_string.presence || '',
        Debug: Proscenium.config.debug
      }.to_json)
    end

    def build_to_string(path, cache_query_string: '')
      ActiveSupport::Notifications.instrument('build.proscenium', identifier: path) do
        result = Request.build_to_string(path, cache_query_string, @request_config)

        raise BuildError.new(path, result[:response]) unless result[:success]

        result
      end
    end

    def resolve(path)
      ActiveSupport::Notifications.instrument('resolve.proscenium', identifier: path) do
        result = Request.resolve(path, @request_config)

        raise ResolveError.new(path, result[:response]) unless result[:success]

        result[:response]
      end
    end

    def compile
      result = Request.compile(@request_config)
      result[:success]
    end

    private

    # Build the ENV variables as determined by `Proscenium.config.env_vars` and
    # `Proscenium::DEFAULT_ENV_VARS` to pass to esbuild.
    def env_vars
      ENV['NODE_ENV'] = ENV.fetch('RAILS_ENV', nil)
      ENV.slice(*Proscenium.config.env_vars + Proscenium::DEFAULT_ENV_VARS)
    end

    def gem_root
      Pathname.new(__dir__).join('..', '..').to_s
    end
  end
end
