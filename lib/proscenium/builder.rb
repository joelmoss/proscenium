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

      attach_function :build, [
        :string,      # path or entry point. multiple can be given by separating with a semi-colon
        :string,      # base URL of the Rails app. eg. https://example.com
        :string,      # path to import map, relative to root
        :string,      # ENV variables as a JSON string

        # Config
        :string,      # Rails application root
        :string,      # Proscenium gem root
        :environment, # Rails environment as a Symbol
        :bool,        # code splitting enabled?
        :bool         # debugging enabled?
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
      attr_reader :error, :path

      def initialize(path, error)
        error = Oj.load(error, mode: :strict).deep_transform_keys(&:underscore)

        super "Failed to build '#{path}' -- #{error['text']}"
      end
    end

    class ResolveError < StandardError
      attr_reader :error_msg, :path

      def initialize(path, error_msg)
        super "Failed to resolve '#{path}' -- #{error_msg}"
      end
    end

    def self.build(path, root: nil, base_url: nil)
      new(root: root, base_url: base_url).build(path)
    end

    def self.resolve(path, root: nil)
      new(root: root).resolve(path)
    end

    def initialize(root: nil, base_url: nil)
      @root = root || Rails.root
      @base_url = base_url
    end

    def build(path) # rubocop:disable Metrics/AbcSize
      ActiveSupport::Notifications.instrument('build.proscenium', identifier: path) do
        result = Request.build(path, @base_url, import_map, env_vars.to_json,
                               @root.to_s,
                               Pathname.new(__dir__).join('..', '..').to_s,
                               Rails.env.to_sym,
                               Proscenium.config.code_splitting,
                               Proscenium.config.debug)

        raise BuildError.new(path, result[:response]) unless result[:success]

        result[:response]
      end
    end

    def resolve(path)
      ActiveSupport::Notifications.instrument('resolve.proscenium', identifier: path) do
        result = Request.resolve(path, import_map, @root.to_s,
                                 Pathname.new(__dir__).join('..', '..').to_s,
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
  end
end
