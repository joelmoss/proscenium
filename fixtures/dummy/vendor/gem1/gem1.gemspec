# frozen_string_literal: true

require_relative 'lib/gem1/version'

Gem::Specification.new do |spec|
  spec.name = 'gem1'
  spec.version = Gem1::VERSION
  spec.authors = ['Joel Moss']
  spec.email = ['joel@developwithstyle.com']
  spec.required_ruby_version = '>= 2.7.0'
  spec.summary = 'Test gem 1'

  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.add_dependency 'rails', '>= 7.0.4'
end
