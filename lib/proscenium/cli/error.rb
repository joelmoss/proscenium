# frozen_string_literal: true

module Proscenium
  module CLI
    # Every failure the CLI reports: a stable code, the exit status it maps to, and text that states
    # the problem, its cause and the fix. The catalog is the single source; golden-output tests pin
    # the human text and the JSON event for each entry (test/cli/golden/).
    class Error < StandardError
      EXIT = { success: 0, internal: 1, input: 2, unsupported: 3, drift: 4, integrity: 5,
               native: 6, busy: 7, interrupted: 8 }.freeze

      # code => [exit, message template, fix template]. Templates take keyword arguments.
      CATALOG = {
        'PSM-E-USAGE' => [
          :input, '%<detail>s', 'Run `bundle exec proscenium --help` for usage.'
        ],
        'PSM-E-INTERNAL' => [
          :internal, 'Unexpected error: %<detail>s',
          'This is a bug in Proscenium. Please report it at ' \
          'https://github.com/joelmoss/proscenium/issues with the output above.'
        ]
      }.freeze

      attr_reader :code, :fix, :details

      def initialize(code, details: {}, **args)
        @code = code
        status, message, fix = CATALOG.fetch(code)
        @status = status
        @fix = format(fix, **args)
        @details = details
        super(format(message, **args))
      end

      def exit_status = EXIT.fetch(@status)
    end
  end
end
