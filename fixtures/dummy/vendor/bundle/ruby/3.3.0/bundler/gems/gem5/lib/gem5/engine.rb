# frozen_string_literal: true

require 'proscenium'

module Gem5
  class Engine < ::Rails::Engine
    # isolate_namespace Gem5
    engine_name 'gem5'

    initializer 'gem5.autoload' do
      # ActiveSupport::Dependencies.autoload_paths << "#{root}/app"

      # Rails.autoloaders.main.push_dir(root.join('app'), namespace: Gem5)

      ActiveSupport::Dependencies.autoload_paths.delete("#{root}/app/components")
      Rails.autoloaders.main.push_dir("#{root}/app/components", namespace: Gem5::Components)
    end
  end
end
