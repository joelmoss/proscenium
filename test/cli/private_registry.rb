# frozen_string_literal: true

require 'base64'
require 'uri'
require 'digest'
require 'json'
require 'rubygems/package'
require 'socket'
require 'stringio'
require 'zlib'

# A private registry for scoped packages, for C31 (#154): it answers only requests that carry its
# token, and logs every request, so a test can show the manager authenticated with the app's own
# .npmrc and that nothing asked it for a gem. Each package is version 1.0.0; `packages` maps its
# name to extra package.json fields, such as scripts (C14).
class PrivateRegistry
  TOKEN = 'proscenium-test-token-c31'
  PACKAGE = '@private/pkg'

  attr_reader :requests, :port

  def initialize(packages = { PACKAGE => {} })
    @server = TCPServer.new('127.0.0.1', 0)
    @port = @server.addr[1]
    @requests = Queue.new
    @tarballs = packages.to_h { |name, fields| [name, tarball(name, fields)] }
    @thread = Thread.new { loop { serve(@server.accept) } }
  end

  def url = "http://127.0.0.1:#{port}/"

  # The app's .npmrc lines that point the scope here and authenticate.
  def npmrc = "@private:registry=#{url}\n//127.0.0.1:#{port}/:_authToken=#{TOKEN}\n"

  def stop
    @thread.kill
    @server.close
  end

  def logged
    list = []
    list << @requests.pop until @requests.empty?
    list
  end

  private

  def serve(client)
    request = client.gets.to_s
    headers = {}
    while (line = client.gets) && line != "\r\n"
      key, value = line.split(':', 2)
      headers[key.downcase] = value.to_s.strip
    end
    path = request.split[1].to_s
    authed = headers['authorization'] == "Bearer #{TOKEN}"
    @requests << [path, authed]
    status, type, body = respond(path, authed)
    client.write("HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}" \
                 "\r\nConnection: close\r\n\r\n#{body}")
  rescue IOError, SystemCallError
    nil
  ensure
    client&.close
  end

  def respond(path, authed)
    return ['401 Unauthorized', 'application/json', '{}'] unless authed

    name = URI.decode_www_form_component(path.delete_prefix('/')).sub(%r{/-/.*}, '')
    tarball = @tarballs[name]
    if tarball.nil?
      ['404 Not Found', 'application/json', '{}']
    elsif path.end_with?('.tgz')
      ['200 OK', 'application/octet-stream', tarball]
    else
      ['200 OK', 'application/json', JSON.generate(packument(name, tarball))]
    end
  end

  def packument(name, tarball)
    integrity = "sha512-#{Base64.strict_encode64(Digest::SHA512.digest(tarball))}"
    version = { 'name' => name, 'version' => '1.0.0',
                'dist' => { 'tarball' => "#{url}#{name}/-/#{name.split('/').last}-1.0.0.tgz",
                            'integrity' => integrity } }
    { 'name' => name, 'dist-tags' => { 'latest' => '1.0.0' }, 'versions' => { '1.0.0' => version } }
  end

  def tarball(name, fields)
    manifest = { 'name' => name, 'version' => '1.0.0' }.merge(fields)
    tar = StringIO.new(+'')
    Gem::Package::TarWriter.new(tar) do |writer|
      { 'package/package.json' => JSON.generate(manifest),
        'package/index.js' => "module.exports = 'private'\n" }.each do |file, body|
        writer.add_file(file, 0o644) { it.write(body) }
      end
    end
    gz = StringIO.new(+'')
    writer = Zlib::GzipWriter.new(gz)
    writer.write(tar.string)
    writer.close
    gz.string
  end
end
