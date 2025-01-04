# frozen_string_literal: true

require_relative 'lib/gem5/version'

Gem::Specification.new do |spec|
  spec.name = 'gem5'
  spec.version = Gem5::VERSION
  spec.authors = ['Joel Moss']
  spec.email = ['joel@developwithstyle.com']
  spec.required_ruby_version = '>= 2.7.0'
  spec.summary = 'Test gem 5'

  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.add_dependency 'rails', '>= 7.0.4'
end
