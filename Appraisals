# frozen_string_literal: true

# ActiveSupport 8.0 passes JSON.generate a `quirks_mode:` keyword that json 3 rejects
# (ArgumentError: unknown keyword: quirks_mode), so it stays on json 2.
appraise 'rails-8' do
  gem 'rails', '~> 8.0.3'
  gem 'json', '< 3'
end

appraise 'rails-8.1' do
  gem 'rails', '~> 8.1.1'
end
