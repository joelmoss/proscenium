# frozen_string_literal: true

require 'active_support/log_subscriber'

module Proscenium
  class LogSubscriber < ActiveSupport::LogSubscriber
    def sideload(event)
      path = event.payload[:identifier]
      sideloaded = event.payload[:sideloaded].relative_path_from(Rails.root)

      info do
        "  #{color('[Proscenium]', nil, bold: true)} Sideloading #{path} from #{sideloaded}"
      end
    end

    def build(event)
      path = event.payload[:identifier]
      path = CGI.unescape(path) if path.start_with?(/https?%3A%2F%2F/)

      info do
        message = "#{color('[Proscenium]', nil, bold: true)} Building /#{path}"
        message << " (Duration: #{event.duration.round(1)}ms | Allocations: #{event.allocations})"
      end
    end

    def resolve(event)
      path = event.payload[:identifier]
      path = CGI.unescape(path) if path.start_with?(/https?%3A%2F%2F/)

      info do
        message = "  #{color('[Proscenium]', nil, bold: true)} Resolving #{path}"
        message << " (Duration: #{event.duration.round(1)}ms | Allocations: #{event.allocations})"
      end
    end
  end
end

Proscenium::LogSubscriber.attach_to :proscenium
