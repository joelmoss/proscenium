# frozen_string_literal: true

require 'json'

module Proscenium
  module CLI
    # Writes what the CLI tells the user: human text, or with `--json` newline-delimited,
    # schema-versioned events on stdout. Errors go to stderr as text, or to stdout as an event.
    # Human text is coloured only on a terminal, and never with NO_COLOR set or TERM=dumb.
    class Reporter
      SCHEMA = 1
      STYLES = { bold: 1, dim: 2, red: 31, green: 32, yellow: 33, cyan: 36 }.freeze
      DIFF_STYLES = { '---' => [:bold], '+++' => [:bold], '@@' => [:cyan], '+' => [:green],
                      '-' => [:red] }.freeze

      # "1 gem", "2 gems".
      def self.count(number, one, many = "#{one}s") = "#{number} #{number == 1 ? one : many}"

      def initialize(out:, err:, json: false, quiet: false)
        @out = out
        @err = err
        @json = json
        @quiet = quiet
      end

      def json? = @json

      # `text` in `styles` for stdout, or as it is when stdout is not a terminal or is JSON.
      def paint(text, *styles) = @json ? text : style(@out, text, *styles)

      # A unified diff with removed lines red, added lines green and hunk headers cyan.
      def paint_diff(diff)
        diff.lines(chomp: true).map do |line|
          prefix = DIFF_STYLES.keys.find { line.start_with?(it) }
          prefix ? paint(line, *DIFF_STYLES[prefix]) : line
        end.join("\n") + (diff.end_with?("\n") ? "\n" : '')
      end

      # A line of the human summary, or an event in JSON mode.
      def info(message, event: 'info', phase: nil, **details)
        if @json
          emit(event:, phase:, status: 'ok', message:, details:)
        elsif !@quiet
          @out.puts message
        end
      end

      # A command's result rather than its progress (the version, the usage, inspect's report):
      # printed even with --quiet, which would otherwise leave such a command saying nothing.
      def result(message, event:, **details)
        @json ? emit(event:, status: 'ok', message:, details:) : @out.puts(message)
      end

      # One JSON document on stdout, for a command whose output is a report (`inspect --json`).
      def document(hash) = @out.puts(JSON.generate(hash))

      # A problem that does not stop the command.
      def warning(error, phase: nil)
        if @json
          emit(event: 'warning', phase:, status: 'warning', code: error.code,
               message: error.message, fix: error.fix, details: error.details)
        else
          problem('Warning:', :yellow, error)
        end
      end

      def error(error, phase: nil, manager: nil)
        if @json
          emit(event: 'error', phase:, status: 'error', code: error.code, message: error.message,
               fix: error.fix, manager:, details: error.details)
        else
          problem('Error:', :red, error)
        end
      end

      private

      # A problem for a person: what happened, a blank line, what to do, and the code to search
      # the docs for. A blank line ends it, apart from whatever follows.
      def problem(label, colour, error)
        @err.puts "#{style(@err, label, :bold, colour)} #{error.message}"
        @err.puts
        @err.puts "#{style(@err, 'To fix:', :bold)} #{error.fix}"
        @err.puts style(@err, "(#{error.code})", :dim)
        @err.puts
      end

      def style(io, text, *styles)
        return text if styles.empty? || !colour?(io)

        "\e[#{styles.map { STYLES.fetch(it) }.join(';')}m#{text}\e[0m"
      end

      def colour?(io)
        io.respond_to?(:tty?) && io.tty? && ENV['NO_COLOR'].to_s.empty? && ENV['TERM'] != 'dumb'
      end

      def emit(**event)
        @out.puts JSON.generate({ schema: SCHEMA }.merge(event.compact.reject { |_, v| v == {} }))
      end
    end
  end
end
