# frozen_string_literal: true

require 'json'

module Proscenium
  module CLI
    # Writes what the CLI tells the user: human text, or with `--json` newline-delimited,
    # schema-versioned events on stdout. Errors go to stderr as text, or to stdout as an event.
    class Reporter
      SCHEMA = 1

      def initialize(out:, err:, json: false, quiet: false)
        @out = out
        @err = err
        @json = json
        @quiet = quiet
      end

      def json? = @json

      # A line of the human summary, or an event in JSON mode.
      def info(message, event: 'info', phase: nil, **details)
        if @json
          emit(event:, phase:, status: 'ok', message:, details:)
        elsif !@quiet
          @out.puts message
        end
      end

      def error(error, phase: nil, manager: nil)
        if @json
          emit(event: 'error', phase:, status: 'error', code: error.code, message: error.message,
               fix: error.fix, manager:, details: error.details)
        else
          @err.puts "#{error.code}: #{error.message}"
          @err.puts error.fix
        end
      end

      private

      def emit(**event)
        @out.puts JSON.generate({ schema: SCHEMA }.merge(event.compact.reject { |_, v| v == {} }))
      end
    end
  end
end
