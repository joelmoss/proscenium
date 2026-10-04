# frozen_string_literal: true

# Stage A fixture: React is a peer the app provides, ms 2.0.0 is the gem's own dependency.
Gem::Specification.new do |spec|
  spec.name = 'stage_a_widget_a'
  spec.version = '1.0.0'
  spec.authors = ['Joel Moss']
  spec.summary = 'Stage A fixture: a gem with a React peer and its own ms'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'
  spec.files = %w[package.json index.js index.css]
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['proscenium.dependencies'] = 'true'
end
