# frozen_string_literal: true

require_relative 'lib/proscenium/version'

Gem::Specification.new do |spec|
  spec.name          = 'proscenium'
  spec.version       = Proscenium::VERSION
  spec.authors       = ['Joel Moss']
  spec.email         = ['joel@developwithstyle.com']

  spec.summary       = 'The engine powering your Rails frontend'
  spec.homepage      = 'https://github.com/joelmoss/proscenium'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/joelmoss/proscenium'
  spec.metadata['changelog_uri'] = 'https://github.com/joelmoss/proscenium/releases'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir[
    'lib/proscenium/**/*',
    'lib/tasks/**/*',
    'lib/proscenium.rb',
    'CODE_OF_CONDUCT.md',
    'README.md',
    'LICENSE.txt']
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', ['>= 7.1.0', '< 9.0']
  spec.add_dependency 'countries', '~> 6.0.0'
  spec.add_dependency 'ffi', '~> 1.17.0'
  spec.add_dependency 'literal', '~> 1.0'
  spec.add_dependency 'oj', '~> 3.13'
  spec.add_dependency 'phonelib', '~> 0.8.8'
  spec.add_dependency 'railties', ['>= 7.1.0', '< 9.0']
  spec.add_dependency 'ruby-next', '~> 1.0.1'
end
