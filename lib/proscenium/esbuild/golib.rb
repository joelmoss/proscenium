# frozen_string_literal: true

require 'ffi'
require 'oj'

module Proscenium
  class Esbuild::Golib
    class Result < FFI::Struct
      layout :success, :bool,
             :response, :string
    end

    module Request
      extend FFI::Library
      ffi_lib Pathname.new(__dir__).join('../../../main.so').to_s

      enum :environment, [:development, 1, :test, :production]

      attach_function :build, [
        :string,      # path or entry point
        :string,      # root
        :environment, # Rails environment as a Symbol
        :string,      # path to import map, relative to root
        :bool         # debugging enabled?
      ], Result.by_value

      attach_function :resolve, [
        :string,      # path or entry point
        :string,      # root
        :environment, # Rails environment as a Symbol
        :string       # path to import map, relative to root
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

    def initialize(root: nil)
      @root = root || Rails.root
    end

    def self.resolve(path)
      new.resolve(path)
    end

    def self.build(path)
      new.build(path)
    end

    def build(path)
      result = Request.build(path, @root.to_s, Rails.env.to_sym, import_map, false)
      raise BuildError.new(path, result[:response]) unless result[:success]

      result[:response]
    end

    def resolve(path)
      result = Request.resolve(path, @root.to_s, Rails.env.to_sym, import_map)
      raise ResolveError.new(path, result[:response]) unless result[:success]

      result[:response]
    end

    private

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
