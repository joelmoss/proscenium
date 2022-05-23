# frozen_string_literal: true

module Proscenium
  module Middleware
    extend ActiveSupport::Autoload

    autoload :Manager
    autoload :Base
    autoload :Runtime
    autoload :Static
    autoload :Javascript
    autoload :React
    autoload :Solid
    autoload :Jsx
    autoload :Stylesheet
  end
end
