#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require 'proscenium'
require 'benchmark/ips'

puts RUBY_DESCRIPTION

root = Pathname.new(__dir__).join('test', 'internal')
path = 'lib/foo.js'

Benchmark.ips do |x|
  # ruby 3.2.2 (2023-03-30 revision e51014f9c0) +YJIT [arm64-darwin22]
  # Warming up --------------------------------------
  #     proscenium build   138.000  i/100ms
  # Calculating -------------------------------------
  #     proscenium build      1.380k (± 1.1%) i/s -      6.900k in   5.000274s
  x.report('proscenium build') do
    Proscenium::Builder.new(root: root).build(path)
  end
end
