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

    # The compiled Go library. It ships in the platform gems only, gated in the gemspec, so a
    # host that matches no platform gem installs the platform-less gem and finds nothing here.
    LIBRARY_PATH = Pathname.new(__dir__).join('ext/proscenium')

    # Raised in place of letting `ffi_lib` fail on its own. FFI reports a missing library as
    # `Could not open library <path>` followed by the system search paths, which reads like a
    # broken install and says nothing about platforms - so the one thing the reader needs to know,
    # that Proscenium ships no binary for their platform, is the one thing it leaves out.
    class UnsupportedPlatform < Error
      def initialize(path)
        super(<<~MESSAGE)
          Proscenium has no compiled library for this platform (#{Gem::Platform.local}).

          Proscenium is a Ruby gem wrapped around a Go library, so it ships a separate gem per
          platform. Yours matched none of them, so you have the platform-less gem, which carries
          no library at all. Nothing is corrupted - this platform is simply not built for.

          Expected the library at: #{path}

          The supported platforms are listed in the README. If yours should be among them, please
          open an issue at https://github.com/joelmoss/proscenium/issues.
        MESSAGE
      end
    end

    module Request
      extend FFI::Library

      raise UnsupportedPlatform, LIBRARY_PATH unless LIBRARY_PATH.exist?

      ffi_lib LIBRARY_PATH.to_s

      enum :environment, [:development, 1, :test, :production]

      # `blocking: true` releases the GVL for the duration of the call, so a build/resolve
      # doesn't stall unrelated Ruby threads (eg. other requests in a multi-threaded server).
      # Safe to do because the Go side shares nothing between calls: each call parses its own
      # config, and the caches that outlive a call (i18n, svg, npm replacements) carry their own
      # locks. See the note in main.go. There is no serialising mutex any more; a new piece of
      # global state on the Go side needs its own.

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

      # One esbuild message as text: its text, detail and location on one line, then each note
      # with its own location on a line of its own. A note is where a recovered Go panic carries
      # its stack, and where a failure inside a nested build names the file that imported it -
      # without this they never left the JSON.
      def self.format_message(message)
        msg = message['Text'].to_s.dup
        msg << ' - ' << message['Detail'] if message['Detail'].is_a?(String)
        msg << format_location(message['Location'])
        Array(message['Notes']).each do |note|
          msg << "\n" << note['Text'].to_s << format_location(note['Location'])
        end

        msg
      end

      def self.format_location(location)
        location ? " at #{location['File']}:#{location['Line']}:#{location['Column']}" : ''
      end

      # Go always answers with a JSON object. Anything else - a nil pointer, a bare scalar, text -
      # is a contract violation, and is shown as the message rather than replaced by a parse error
      # that hides it.
      def self.parse_json(json)
        parsed = JSON.parse(json, strict: true)
        parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError, TypeError
        nil
      end

      def initialize(path, error)
        @path = path
        @error = self.class.parse_json(error) || { 'Text' => error.to_s }

        super("Failed to build #{path} - #{self.class.format_message(@error)}")
      end
    end

    # Raised by `compile` with every error esbuild reported. It used to return `false` and throw
    # the messages away, so a failed precompile gave no reason at all.
    class CompileError < Error
      attr_reader :messages

      def initialize(messages)
        @messages = BuildError.parse_json(messages) || { 'Errors' => [{ 'Text' => messages.to_s }] }

        errors = Array(@messages['Errors']).map { |message| BuildError.format_message(message) }

        super("Failed to compile assets - #{errors.join("\n")}")
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
        # The FFI hands back ASCII-8BIT. These are paths, and Go writes them as UTF-8.
        url_path = read_and_free(raw[:url_path])&.force_encoding(Encoding::UTF_8)
        abs_path = read_and_free(raw[:abs_path])&.force_encoding(Encoding::UTF_8)

        raise ResolveError.new(path, url_path) unless success

        [url_path, abs_path]
      end
    end

    # Returns true, or raises CompileError with esbuild's messages.
    def compile
      raw = Request.compile(@request_config)
      messages = read_and_free(raw[:messages])

      raise CompileError, messages unless raw[:success]

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
