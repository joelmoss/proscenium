#!/usr/bin/env ruby
# frozen_string_literal: true

# require 'esbuild'
require 'proscenium'
require 'open3'
require 'benchmark/ips'

puts RUBY_DESCRIPTION

root = Pathname.new(__dir__).join('test', 'internal')
path = 'lib/foo.js'

Benchmark.ips do |x|
  x.report('proscenium esbuild') do
    Proscenium::Esbuild.build(path, root: root)
  end

  x.report('proscenium golib') do
    Proscenium::Esbuild::Golib.new(root: root).build(path)
  end

  x.report('esbuild-cli') do
    Open3.capture3(['/Users/joelmoss/dev/esbuild-ruby/bin/esbuild', path].join(' '))
  end

  # x.report('esbuild build') do
  #   Esbuild.build(entry_points: [path], write: false, abs_working_dir: root.to_s)
  # end

  x.compare!
end
