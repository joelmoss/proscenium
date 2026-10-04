# frozen_string_literal: true

# Stage C control (C01): imports a package without declaring it, so it depends on the app's own
# copy, as gems did before #154. It never participates.
Gem::Specification.new do |spec|
  spec.name = 'stage_a_app_dependent'
  spec.version = '1.0.0'
  spec.authors = ['Joel Moss']
  spec.summary = 'Stage C fixture: a gem that relies on the app for its JavaScript dependencies'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'
  spec.files = %w[index.js]
  spec.metadata['rubygems_mfa_required'] = 'true'
end
