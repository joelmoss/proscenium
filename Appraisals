# frozen_string_literal: true

# ActiveSupport 7.2 and 8.0 pass JSON.generate a `quirks_mode:` keyword that json 3 rejects
# (ArgumentError: unknown keyword: quirks_mode), so those two stay on json 2.
appraise 'rails-7.2' do
  gem 'rails', '~> 7.2.0'
  gem 'json', '< 3'
end

appraise 'rails-8' do
  gem 'rails', '~> 8.0.3'
  gem 'json', '< 3'
end

appraise 'rails-8.1' do
  gem 'rails', '~> 8.1.1'
end
