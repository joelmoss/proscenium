# frozen_string_literal: true

module Proscenium
  class Connection < ActionCable::Connection::Base
    identified_by :uid

    def connect
      self.uid = request.params[:uid]
      logger.add_tags(uid)
    end
  end
end
