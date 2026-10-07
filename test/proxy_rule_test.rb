# frozen_string_literal: true

require_relative 'cli/helper'
require 'net/http'
require 'open3'
require 'socket'
require 'tmpdir'

# C54 (#154): the nginx rule the consumer guide documents, taken from the guide verbatim, serves
# the package paths unbundled pages load (pnpm's and Bun's stores, a context's nested copies)
# while the dotfile deny it sits in front of still denies everything else. Without the rule, the
# deny blocks those paths too, which is the control that the rule is what lets them through.
#
# Needs nginx on PATH. The package-manager job installs it on Linux, and there the test fails rather than
# skips.
describe 'the documented proxy rule' do
  GUIDE = File.expand_path('../docs/guides/rubygem_npm_dependencies.md', __dir__)
  ALLOWED = %w[/node_modules/.pnpm/ms@2.1.3/node_modules/ms/index.js
               /node_modules/.bun/ms@2.1.3/node_modules/ms/index.js
               /.proscenium/packages/widget/node_modules/ms/index.js].freeze
  DENIED = %w[/.env /assets/.git/config].freeze

  before do
    unless system('nginx', '-v', err: File::NULL)
      flunk 'nginx is not on PATH' if ENV['STAGE_A'] && RUBY_PLATFORM.include?('linux')
      skip 'needs nginx on PATH'
    end
    @dir = Dir.mktmpdir('proxy_rule')
  end

  after do
    if @pid
      Process.kill('TERM', @pid)
      Process.wait(@pid)
    end
    FileUtils.rm_rf(@dir) if @dir
  end

  def rule = File.read(GUIDE)[/```nginx\n(.*?)```/m, 1] || flunk('the guide has no nginx block')

  def free_port = TCPServer.open('127.0.0.1', 0) { it.addr[1] }

  # nginx in the foreground under @dir: the app's server with `locations`, and an upstream that
  # answers every request it is passed with its path.
  def serve(locations)
    port = free_port
    upstream = free_port
    temp = %w[client_body proxy fastcgi uwsgi scgi].map { "#{it}_temp_path #{@dir}/#{it};" }
    File.write(File.join(@dir, 'nginx.conf'), <<~CONF)
      daemon off;
      pid #{@dir}/nginx.pid;
      error_log #{@dir}/error.log;
      events {}
      http {
        access_log off;
        #{temp.join("\n  ")}
        upstream app { server 127.0.0.1:#{upstream}; }
        server { listen 127.0.0.1:#{upstream}; location / { return 200 "app $uri"; } }
        server {
          listen 127.0.0.1:#{port};
          #{locations}
          location / { proxy_pass http://app; }
        }
      }
    CONF
    # -e: before it reads the config, nginx opens its compiled-in error log, which a user may not
    # be able to write.
    @pid = spawn('nginx', '-p', @dir, '-e', File.join(@dir, 'error.log'), '-c',
                 File.join(@dir, 'nginx.conf'), err: File::NULL)
    50.times do
      return port if listening?(port)

      sleep 0.1
    end
    flunk "nginx did not start: #{File.read(File.join(@dir, 'error.log'))}"
  end

  def listening?(port)
    TCPSocket.new('127.0.0.1', port).close
    true
  rescue SystemCallError
    false
  end

  def get(port, path) = Net::HTTP.get_response('127.0.0.1', path, port)

  it 'serves the package paths and denies other dotfiles' do
    port = serve(rule)

    ALLOWED.each do |path|
      response = get(port, path)

      assert_equal ['200', "app #{path}"], [response.code, response.body], path
    end
    DENIED.each { assert_equal '403', get(port, it).code, it }
  end

  it 'is what lets them through: the dotfile deny alone blocks them' do
    port = serve(rule.lines.grep_v(/\^~/).join)

    ALLOWED.each { assert_equal '403', get(port, it).code, it }
  end
end
