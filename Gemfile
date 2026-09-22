# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in proscenium.gemspec
gemspec

gem 'amazing_print'
gem 'debug'

group :development do
  gem 'appraisal'
  gem 'benchmark-ips'
  gem 'rubocop-minitest', require: false
  gem 'rubocop-packaging', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rake', require: false
end

group :test do
  gem 'capybara'
  gem 'database_cleaner-active_record', require: 'database_cleaner/active_record'
  gem 'fakefs', require: 'fakefs/safe'
  gem 'gem1', path: './fixtures/dummy/vendor/gem1'
  gem 'gem2', path: './fixtures/external/gem2'
  gem 'gem3', path: './fixtures/dummy/vendor/gem3'
  gem 'gem4', path: './fixtures/external/gem4'
  gem 'gem5', path: './fixtures/dummy/vendor/bundle/ruby/3.3.0/bundler/gems/gem5'
  gem 'gem_file', path: './fixtures/dummy/vendor/gem_file'
  gem 'gem_npm', path: './fixtures/dummy/vendor/gem_npm'
  gem 'gem_npm_ext', path: './fixtures/external/gem_npm_ext'
  gem 'maxitest'
  gem 'minitest-difftastic'
  gem 'minitest-focus'
  gem 'minitest-spec-rails'
  gem 'sqlite3'

  # Windows has no system zoneinfo database, so TZInfo finds no data source and the dummy app
  # cannot boot. Every other platform reads /usr/share/zoneinfo and never needs this.
  #
  # Deliberately not `platforms: :windows`. A platform-gated dependency is recorded in the
  # lockfile's DEPENDENCIES but resolved to no spec, so the Windows job would have to re-resolve
  # it at install time instead of installing what the lockfile says. It is a data gem with no
  # extension, so carrying it everywhere costs a megabyte and nothing else.
  gem 'tzinfo-data'
end
