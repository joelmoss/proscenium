# frozen_string_literal: true

module Benchmarks
  class Build
    ROOT = Pathname.new(__dir__).join('../', 'fixtures', 'dummy')

    def initialize
      path = 'lib/foo.js'

      Benchmark.ips do |x|
        # ruby 3.3.6 (2024-11-05 revision 75015d4c1f) +YJIT [arm64-darwin24]
        # Warming up --------------------------------------
        #     proscenium build   110.000 i/100ms
        # Calculating -------------------------------------
        #     proscenium build      1.087k (± 7.7%) i/s  (920.02 μs/i) -      5.390k in   5.003855s
        x.report('proscenium build') do
          Proscenium::Builder.new(root: ROOT).build_to_string(path)
        end
      end
    end
  end
end
