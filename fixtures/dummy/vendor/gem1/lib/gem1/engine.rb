# frozen_string_literal: true

require 'proscenium'

module Gem1
  class Engine < ::Rails::Engine
    # isolate_namespace Gem1
    engine_name 'gem1'

    config.proscenium.engines << self

    initializer 'gem1.autoload' do
      # ActiveSupport::Dependencies.autoload_paths << "#{root}/app"

      # Rails.autoloaders.main.push_dir(root.join('app'), namespace: Gem1)

      ActiveSupport::Dependencies.autoload_paths.delete("#{root}/app/components")
      Rails.autoloaders.main.push_dir("#{root}/app/components", namespace: Gem1::Components)
    end
  end
end
