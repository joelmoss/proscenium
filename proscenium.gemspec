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
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/joelmoss/proscenium'
  spec.metadata['changelog_uri'] = 'https://github.com/joelmoss/proscenium/releases'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files          = Dir['CODE_OF_CONDUCT.md', 'README.md', 'LICENSE', 'lib/**/*', 'bin/**/*']
  spec.bindir         = 'bin'
  spec.executables << 'esbuild'
  spec.executables << 'parcel_css'
  spec.require_paths = ['lib']
  spec.post_install_message = 'Thanks for installing!'

  spec.add_dependency 'actioncable', '>= 6.1.0'
  spec.add_dependency 'activesupport', '>= 6.1.0'
  spec.add_dependency 'listen', '~> 3.0'
  spec.add_dependency 'oj', '~> 3.13'
  spec.add_dependency 'railties', '>= 6.1.0'
  spec.add_dependency 'view_component', '~> 2.0'
end
