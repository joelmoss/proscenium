# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.3.6'

# Specify your gem's dependencies in proscenium.gemspec
gemspec

gem 'amazing_print'
gem 'debug'
gem 'rails', '~> 7.0'

# Playground
gem 'appraisal'
gem 'gems'
gem 'htmlbeautifier'
gem 'phlexible'
gem 'phlex-markdown', github: 'phlex-ruby/phlex-markdown'
gem 'rouge'

group :development do
  gem 'benchmark-ips'
  gem 'localhost'
  gem 'puma'
  gem 'rubocop'
  gem 'rubocop-minitest', require: false
  gem 'rubocop-packaging', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rake', require: false
  gem 'sqlite3'
  gem 'web-console'
end
# gem 'gem2'
gem 'gem2', path: './fixtures/external/gem2'
group :test do
  gem 'capybara'
  gem 'cuprite'
  gem 'database_cleaner-active_record', require: 'database_cleaner/active_record'
  gem 'fakefs', require: 'fakefs/safe'
  gem 'gem1', path: './fixtures/dummy/vendor/gem1'
  gem 'gem3', path: './fixtures/dummy/vendor/gem3'
  gem 'gem4', path: './fixtures/external/gem4'
  gem 'gem5', path: './fixtures/dummy/vendor/bundle/ruby/3.3.0/bundler/gems/gem5'
  gem 'gem_file', path: './fixtures/dummy/vendor/gem_file'
  gem 'maxitest'
  gem 'minitest-focus'
  gem 'minitest-spec-rails'
  gem 'phlex-testing-capybara'
  gem 'view_component'
end
