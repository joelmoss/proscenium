#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'

require 'proscenium'
require 'benchmark/ips'

puts RUBY_DESCRIPTION

raise ArgumentError, 'Must provide a benchmark name.' if ARGV.empty?

name = ARGV.first

require_relative "./benchmarks/#{name}"

name = ActiveSupport::Inflector.camelize(name)
ActiveSupport::Inflector.constantize("Benchmarks::#{name}").new
