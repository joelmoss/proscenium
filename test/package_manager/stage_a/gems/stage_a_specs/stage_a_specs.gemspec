# frozen_string_literal: true

# Stage D fixture (C10): one dependency of every kind a gem may declare, each of which must install
# from its context exactly as from a native workspace package. Its manifest version is not the
# gem's: the two are independent.
Gem::Specification.new do |spec|
  spec.name = 'stage_a_specs'
  spec.version = '1.0.0'
  spec.authors = ['Joel Moss']
  spec.summary = 'Stage D fixture: every dependency spec kind'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'
  spec.files = %w[package.json index.js]
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['proscenium.dependencies'] = 'true'
end
