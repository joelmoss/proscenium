# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require 'proscenium'

module Playground
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    config.hosts << 'proscenium.test'

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # config.autoload_lib(ignore: %w[assets tasks])

    # Autoload Proscenium lib
    lib = Proscenium.root.join('lib')
    config.autoload_paths << lib.to_s
    config.eager_load_paths << lib.to_s
    Rails.autoloaders.main.ignore Array.wrap(%w[ext tasks]).map { lib.join(_1) }

    config.autoload_paths << "#{root}/app/views"
    config.autoload_paths << "#{root}/app/components"
    config.autoload_paths << "#{root}/app/views/layouts"
  end
end
