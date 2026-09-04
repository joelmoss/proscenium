# frozen_string_literal: true

require 'ffi'

module Proscenium
  class Builder
    ENVIRONMENTS = { development: 1, test: 2, production: 3 }.freeze

    class Result < FFI::Struct
      layout :success, :bool,
             :response, :pointer,
             :content_hash, :pointer
    end

    class ResolveResult < FFI::Struct
      layout :success, :bool,
             :url_path, :pointer,
             :abs_path, :pointer
    end

    class CompileResult < FFI::Struct
      layout :success, :bool,
             :messages, :pointer
    end

    module Request
      extend FFI::Library

      ffi_lib Pathname.new(__dir__).join('ext/proscenium').to_s

      enum :environment, [:development, 1, :test, :production]

      # `blocking: true` releases the GVL for the duration of the call, so a build/resolve
      # doesn't stall unrelated Ruby threads (eg. other requests in a multi-threaded server).
      # Safe to do because the Go side serialises these calls itself with a mutex - see main.go.

      attach_function :build_to_string, [
        :string, # Path or entry point.
        :pointer # Config as JSON.
      ], Result.by_value, blocking: true

      attach_function :resolve, [
        :string, # path or entry point
        :pointer # Config as JSON.
      ], ResolveResult.by_value, blocking: true

      attach_function :compile, [
        :pointer # Config as JSON.
      ], CompileResult.by_value, blocking: true

      attach_function :reset_config, [], :void, blocking: true

      attach_function :free_cstr, [:pointer], :void
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

    def self.build_to_string(path, root: nil, **overrides)
      new(root:, **overrides).build_to_string(path)
    end

    def self.resolve(path, root: nil, **overrides)
      new(root:, **overrides).resolve(path)
    end

    def self.compile(root: nil, **overrides)
      new(root:, **overrides).compile
    end

    # Intended for tests only.
    def self.reset_config!
      Request.reset_config
    end

    # `overrides` are merged over the config derived from `Proscenium.config`, and are passed
    # straight through to the Go side. Intended for callers that are not serving a browser request
    # and so want different build settings - `Bundle: false`, `Write: false`, `CodeSplitting: false`
    # - than the app's own configuration. Keys must match `types.ConfigT`; Go silently ignores
    # any it does not know.
    def initialize(root: nil, **overrides)
      config_hash = {
        RootPath: (root || Rails.root).to_s,
        OutputDir: "public#{Proscenium.config.output_dir}",
        GemPath: gem_root,
        Environment: ENVIRONMENTS.fetch(Rails.env.to_sym, 2),
        EnvVars: env_vars,
        CodeSplitting: Proscenium.config.code_splitting,
        RubyGems: Proscenium::BundledGems.paths,
        Bundle: Proscenium.config.bundle,
        Aliases: Proscenium.config.aliases,
        External: Proscenium.config.external,
        Precompile: Proscenium.config.precompile,
        Debug: Proscenium.config.debug
      }.merge(overrides)

      @request_config = self.class.request_config_pointer(config_hash)
    end

    class << self
      # Building the config JSON and copying it into an FFI::MemoryPointer is the only real cost
      # in instantiating a Builder (everything else is memoized attribute reads). Since the
      # config is identical across the vast majority of calls (same root, same Rails env, same
      # Proscenium.config), skip re-serializing and re-allocating it when nothing has changed.
      #
      # Callers keep their own reference to the returned pointer, so a later call replacing the
      # memo does not invalidate a pointer already in use.
      #
      # The hash and its pointer are stored as one frozen pair in one ivar, and assigned once. Two
      # ivars would need a lock: a reader could see a hash already updated while its pointer still
      # pointed at the previous config, and get a build made with someone else's settings. One
      # assignment cannot be observed half-done, so a reader sees either the old pair or the new
      # one - never a mix - and there is no window for a test to have to reproduce.
      def request_config_pointer(config_hash)
        memo = @config_memo
        return memo[1] if memo && memo[0] == config_hash

        pointer = FFI::MemoryPointer.from_string(config_hash.to_json)
        @config_memo = [config_hash, pointer].freeze

        pointer
      end
    end

    def build_to_string(path)
      ActiveSupport::Notifications.instrument('build.proscenium', identifier: path) do
        raw = Request.build_to_string(path, @request_config)
        result = { success: raw[:success], response: read_and_free(raw[:response]),
                   content_hash: read_and_free(raw[:content_hash]) }

        raise BuildError.new(path, result[:response]) unless result[:success]

        result
      end
    end

    def resolve(path)
      ActiveSupport::Notifications.instrument('resolve.proscenium', identifier: path) do
        raw = Request.resolve(path, @request_config)
        success = raw[:success]
        url_path = read_and_free(raw[:url_path])
        abs_path = read_and_free(raw[:abs_path])

        raise ResolveError.new(path, url_path) unless success

        [url_path, abs_path]
      end
    end

    def compile
      raw = Request.compile(@request_config)
      read_and_free(raw[:messages])
      raw[:success]
    end

    private

    # The Go side allocates each of these strings with C.CString, which the Go runtime cannot
    # see or collect - it must be freed from this side once we're done reading it.
    def read_and_free(ptr)
      return nil if ptr.null?

      ptr.read_string
    ensure
      Request.free_cstr(ptr)
    end

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
