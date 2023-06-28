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
  #     proscenium build   123.000  i/100ms
  # Calculating -------------------------------------
  #     proscenium build      1.233k (± 1.2%) i/s -      6.273k in   5.087255s
  x.report('proscenium build') do
    Proscenium::Builder.new(root: root).build(path)
  end
end
