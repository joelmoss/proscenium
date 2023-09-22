# frozen_string_literal: true

require_relative 'lib/gem3/version'

Gem::Specification.new do |spec|
  spec.name = 'gem3'
  spec.version = Gem3::VERSION
  spec.authors = ['Joel Moss']
  spec.email = ['joel@developwithstyle.com']
  spec.required_ruby_version = '>= 2.6.0'
  spec.summary = 'Test gem 1'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.add_dependency 'rails', '>= 7.0.4'
end
