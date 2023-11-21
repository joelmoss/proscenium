# frozen_string_literal: true

module SystemTesting
  class ConsoleError < RuntimeError
  end

  class ConsoleLogger
    attr_reader :logs

    def initialize
      @logs = []
    end

    # Filter out the noise - I believe Runtime.exceptionThrown and Log.entryAdded are the
    # interesting log methods but there might be others you need
    def puts(log_str)
      msg = Message.new(log_str)

      raise ConsoleError, msg.message if msg.method == 'Runtime.exceptionThrown'

      if %w[Runtime.exceptionThrown Log.entryAdded Runtime.consoleAPICalled].include?(msg.method)
        @logs << msg
      end
    end

    def flush
      @logs = []
    end

    def messages
      logs.map(&:message)
    end

    class Message
      attr_reader :body

      def initialize(log_str)
        _symbol, _time, body_raw = log_str.strip.split(' ', 3)
        @body = JSON.parse body_raw
      end

      def level
        if method == 'Log.entryAdded'
          body.dig 'params', 'entry', 'level'
        else
          body.dig 'params', 'type'
        end
      end

      def message
        case method
        when 'Runtime.exceptionThrown'
          body.dig 'params', 'exceptionDetails', 'exception', 'value'
        when 'Log.entryAdded'
          body.dig 'params', 'entry', 'text'
        else
          args = body.dig 'params', 'args'
          args.pluck('value').join(', ')
        end
      end

      def timestamp
        if method == 'Log.entryAdded'
          body.dig 'params', 'entry', 'timestamp'
        else
          body.dig 'params', 'timestamp'
        end
      end

      def stacktrace
        body.dig 'params', 'stackTrace'
      end

      def method
        body['method']
      end
    end
  end
end
