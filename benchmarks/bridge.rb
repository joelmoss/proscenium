# frozen_string_literal: true

module Benchmarks
  class Bridge
    ROOT = Pathname.new(__dir__).join('../', 'fixtures', 'dummy')

    def initialize
      path = 'lib/foo.js'
      builder = Proscenium::Builder.new(root: ROOT)
      config_ptr = builder.instance_variable_get(:@request_config)

      Benchmark.ips do |x|
        x.report('new Builder (config marshal + MemoryPointer)') do
          Proscenium::Builder.new(root: ROOT)
        end

        x.report('build_to_string (full, cached config)') do
          builder.build_to_string(path)
        end

        x.report('FFI resolve call only (cached config)') do
          Proscenium::Builder::Request.resolve(path, config_ptr)
        end

        x.report('pure FFI dispatch (reset_config, void/void)') do
          Proscenium::Builder::Request.reset_config
        end

        x.compare!
      end
    end
  end
end
