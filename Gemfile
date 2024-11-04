# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in proscenium.gemspec
gemspec

gem 'debug'
gem 'rails', '~> 7.0'

# Playground
gem 'htmlbeautifier'
gem 'phlexible'
gem 'rouge'

group :development do
  gem 'benchmark-ips'
  gem 'puma'
  gem 'rubocop'
  gem 'rubocop-minitest', require: false
  gem 'rubocop-packaging', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rake', require: false
  gem 'sqlite3'
  gem 'web-console'
end

group :test do
  gem 'capybara'
  gem 'cuprite'
  gem 'fakefs', require: 'fakefs/safe'
  gem 'gem1', path: './fixtures/dummy/vendor/gem1'
  gem 'gem2', path: './fixtures/external/gem2'
  gem 'gem3', path: './fixtures/dummy/vendor/gem3'
  gem 'gem4', path: './fixtures/external/gem4'
  gem 'maxitest'
  gem 'minitest-focus'
  gem 'minitest-spec-rails'
  gem 'phlex-testing-capybara'
  gem 'view_component', '~> 3.6.0'
end
