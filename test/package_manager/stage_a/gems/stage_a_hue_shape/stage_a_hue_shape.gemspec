# frozen_string_literal: true

# Stage A fixture reproducing hue's awkward traits: its package.json has no `version`, declares
# react and react-dom as plain dependencies plus a `github:` dependency, and is missing from
# `spec.files`. It is installed as a Git source, so the manifest is on disk anyway.
Gem::Specification.new do |spec|
  spec.name = 'stage_a_hue_shape'
  spec.version = '0.5.3.pre1'
  spec.authors = ['Joel Moss']
  spec.summary = "Stage A fixture: hue's package.json shape"
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'
  spec.files = %w[index.js]
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['proscenium.dependencies'] = 'true'
end
