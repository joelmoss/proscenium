#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require 'proscenium'
require 'benchmark/ips'

puts RUBY_DESCRIPTION

root = Pathname.new(__dir__).join('test', 'internal')
path = 'lib/foo.js'

Benchmark.ips do |x|
  x.report('proscenium build') do
    Proscenium::Builder.new(root: root).build(path)
  end

  # x.compare!
end
