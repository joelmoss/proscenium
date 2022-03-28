# frozen_string_literal: true

module Proscenium
  module Middleware
    extend ActiveSupport::Autoload

    autoload :Manager
    autoload :Base
    autoload :Static
  end
end
