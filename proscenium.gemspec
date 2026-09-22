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
  spec.required_ruby_version = '>= 3.3.0'
  # Older RubyGems cannot tell `x86_64-linux-gnu` from `x86_64-linux-musl` and will happily
  # install the wrong one. Refusing outright beats installing a library the host cannot load.
  # Free in practice: Ruby 3.3 already ships a newer RubyGems than this.
  spec.required_rubygems_version = '>= 3.3.22'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/joelmoss/proscenium'
  spec.metadata['changelog_uri'] = 'https://github.com/joelmoss/proscenium/releases'
  spec.metadata['rubygems_mfa_required'] = 'true'

  files = Dir[
    'lib/proscenium/**/*',
    'lib/generators/**/*',
    'lib/tasks/**/*',
    'lib/proscenium.rb',
    'CODE_OF_CONDUCT.md',
    'README.md',
    'LICENSE.txt']

  # The compiled Go library ships in the platform gems only, and the platform build tasks are the
  # only thing that sets this.
  #
  # Without the gate the platform-less gem packs whichever binary happens to be on disk: `rake
  # build` runs the platform compiles as prerequisites and Bundler's own plain-gem action last, in
  # one working tree, so the plain gem inherits the last platform's library. That is not
  # hypothetical - the released 0.25.2 contains an x86-64 Linux ELF. A host that matches no
  # platform gem then gets a library for somebody else's operating system and a dlopen failure,
  # rather than the message in Proscenium::Builder saying which platforms are supported.
  #
  # It cannot be fixed downstream in `push:gem`: that task uploads an archive that has already
  # been built, and rake runs a task once per invocation.
  unless ENV['PROSCENIUM_PACKAGE_EXT']
    files.reject! { |path| path.start_with?('lib/proscenium/ext/') }
  end

  spec.files = files

  # Set by the platform build tasks. Not `gem build --platform`, which RubyGems only applies when
  # the target differs from the platform it is running on: on a Windows host building the Windows
  # gem it silently changes nothing, and out comes a platform-less gem carrying a DLL.
  spec.platform = ENV['PROSCENIUM_PLATFORM'] if ENV['PROSCENIUM_PLATFORM']
  spec.require_paths = ['lib']

  spec.add_dependency 'ffi', '~> 1.17.0'
  spec.add_dependency 'rails', ['>= 7.2.0', '< 9.0']
end
