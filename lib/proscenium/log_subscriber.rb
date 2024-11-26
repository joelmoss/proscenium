# frozen_string_literal: true

require 'active_support/log_subscriber'

module Proscenium
  class LogSubscriber < ActiveSupport::LogSubscriber
    def sideload(event)
      info do
        "  [Proscenium] Side loaded #{event.payload[:identifier]}"
      end
    end

    def build_to_path(event)
      path = event.payload[:identifier]
      cached = event.payload[:cached] ? ' | Cached!' : ''
      path = CGI.unescape(path) if path.start_with?(/https?%3A%2F%2F/)

      info do
        message = "  #{color('[Proscenium]', nil, bold: true)} Building (to path) #{path}"
        message << " (Duration: #{event.duration.round(1)}ms | " \
                   "Allocations: #{event.allocations}#{cached})"
      end
    end

    def build_to_string(event)
      path = event.payload[:identifier]
      path = CGI.unescape(path) if path.start_with?(/https?%3A%2F%2F/)

      info do
        message = "  #{color('[Proscenium]', nil, bold: true)} Building (to string) #{path}"
        message << " (Duration: #{event.duration.round(1)}ms | Allocations: #{event.allocations})"
      end
    end
  end
end

Proscenium::LogSubscriber.attach_to :proscenium
