# frozen_string_literal: true

class Proscenium::Registry
  extend ActiveSupport::Autoload

  autoload :Package
  autoload :BundledPackage
  autoload :RubyGemPackage

  class PackageUnsupportedError < StandardError
    def initialize(name)
      super("Package `#{name}` is not valid; only Ruby gems are supported via the @rubygems scope.")
    end
  end

  class PackageNotInstalledError < StandardError
    def initialize(name)
      super("Package `#{name}` is not found in your bundle; have you installed the Ruby gem?")
    end
  end

  def self.bundled_package(name, host:)
    BundledPackage.new(name, host:).validate!
  end

  def self.ruby_gem_package(name, version, host:)
    RubyGemPackage.new(name, version:, host:).validate!
  end
end
