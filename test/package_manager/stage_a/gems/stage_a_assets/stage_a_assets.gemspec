# frozen_string_literal: true

# Stage A control: self-contained frontend files and no package.json, so it never participates.
Gem::Specification.new do |spec|
  spec.name = 'stage_a_assets'
  spec.version = '1.0.0'
  spec.authors = ['Joel Moss']
  spec.summary = 'Stage A fixture: a self-contained gem without a package.json'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'
  spec.files = %w[index.js util.js index.css base.css]
  spec.metadata['rubygems_mfa_required'] = 'true'
end
