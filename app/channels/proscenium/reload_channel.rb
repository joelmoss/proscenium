# frozen_string_literal: true

module Proscenium
  class ReloadChannel < ActionCable::Channel::Base
    def subscribed
      stream_from 'reload'
    end
  end
end
