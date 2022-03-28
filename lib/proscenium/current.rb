# frozen_string_literal: true

require 'active_support/current_attributes'

module Proscenium
  class Current < ActiveSupport::CurrentAttributes
    attribute :loaded
  end
end
