# frozen_string_literal: true

require 'active_support'

module Proscenium
  class Current < ActiveSupport::CurrentAttributes
    attribute :loaded
  end
end

require 'proscenium/middleware'
require 'proscenium/side_load'
require 'proscenium/helper'
require 'proscenium/railtie'
