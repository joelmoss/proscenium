# frozen_string_literal: true

require 'ffi'
require 'oj'

module Proscenium
  class Esbuild::Golib
    class Result < FFI::Struct
      layout :success, :bool,
             :response, :string
    end

    module Builder
      extend FFI::Library
      ffi_lib 'main.so'

      enum :environment, [:development, 1, :test, :production]

      attach_function :build, %i[string string environment bool], Result.by_value
    end

    class CompileError < StandardError
      attr_reader :error, :path

      def initialize(path, error)
        error = Oj.load(error, mode: :strict).deep_transform_keys(&:underscore)

        super "Failed to build '#{path}' -- #{error['text']}"
      end
    end

    def initialize(root: nil)
      @root = root || Rails.root
    end

    def build(path)
      result = Builder.build(path, @root.to_s, Rails.env.to_sym, true)
      raise CompileError.new(path, result[:response]) unless result[:success]

      result[:response]
    end
  end
end
