# frozen_string_literal: true

require 'socket'
require 'uri'

# A forward proxy for C31 (#154): it relays plain HTTP requests and tunnels CONNECT, and logs the
# target of each, so a test can show a manager reached a registry through it.
class LoggingProxy
  attr_reader :port

  def initialize
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @targets = Queue.new
    @thread = Thread.new { loop { Thread.new(@server.accept) { serve(it) } } }
  end

  def url = "http://127.0.0.1:#{port}"

  def stop
    @thread.kill
    @server.close
  end

  def logged
    list = []
    list << @targets.pop until @targets.empty?
    list
  end

  private

  def serve(client)
    method, target, version = client.gets.to_s.split
    headers = []
    while (line = client.gets) && line != "\r\n"
      headers << line
    end
    @targets << "#{method} #{target}"
    method == 'CONNECT' ? tunnel(client, target) : relay(client, method, target, version, headers)
  rescue IOError, SystemCallError
    nil
  ensure
    client&.close
  end

  def tunnel(client, target)
    host, port = target.split(':')
    upstream = TCPSocket.new(host, port.to_i)
    client.write("HTTP/1.1 200 Connection Established\r\n\r\n")
    pipe(client, upstream)
  end

  def relay(client, method, target, version, headers)
    uri = URI(target)
    upstream = TCPSocket.new(uri.host, uri.port)
    kept = headers.grep_v(/\A(?:proxy-connection|connection):/i)
    request = "#{method} #{uri.request_uri} #{version}\r\n#{kept.join}"
    upstream.write("#{request}Connection: close\r\n\r\n")
    pipe(client, upstream)
  end

  # Copies both ways until either side closes.
  def pipe(client, upstream)
    threads = [[client, upstream], [upstream, client]].map do |from, to|
      Thread.new do
        IO.copy_stream(from, to)
      rescue IOError, SystemCallError
        nil
      ensure
        close_write(to)
      end
    end
    threads.each(&:join)
  ensure
    upstream&.close
  end

  def close_write(io)
    io.close_write
  rescue IOError, SystemCallError
    nil
  end
end
