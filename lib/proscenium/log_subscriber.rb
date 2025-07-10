# frozen_string_literal: true

require 'active_support/log_subscriber'

module Proscenium
  class LogSubscriber < ActiveSupport::LogSubscriber
    def sideload(event)
      path = event.payload[:identifier]
      sideloaded = event.payload[:sideloaded]
      sideloaded = sideloaded.relative_path_from(Rails.root) if sideloaded.is_a?(Pathname)

      info do
        msg = "  #{color('[Proscenium]', nil, bold: true)} Sideloading #{path}"
        sideloaded.is_a?(Pathname) ? msg << " from #{sideloaded}" : msg
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
