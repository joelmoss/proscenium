# frozen_string_literal: true

require 'test_helper'
require 'proscenium/runtime/server'

class Proscenium::Runtime::ServerTest < ActiveSupport::TestCase
  let(:server) { Proscenium::Runtime::Server.new(watch: nil) }

  def request(name, **args)
    server.handle({ 'id' => 1, 'op' => name }.merge(args.transform_keys(&:to_s)))
  end

  describe 'handshake' do
    it 'returns what the plugin needs to bootstrap' do
      reply = request('handshake')

      assert reply[:ok]
      config = reply[:config]
      assert_equal Rails.root.to_s, config[:root]
      assert_equal Proscenium.root.to_s, config[:gemPath]
      assert_equal Proscenium.root.join('lib/proscenium/runtime/bun.js').to_s, config[:pluginPath]
      assert_includes config[:rubyGems].keys, 'proscenium'
      assert_equal 'test', config[:environment]
    end
  end

  describe 'resolve' do
    it 'resolves a bare npm specifier' do
      reply = request('resolve', path: 'pkg')

      assert reply[:ok]
      assert_equal '/node_modules/pkg/index.js', reply[:urlPath]
      assert_equal Rails.root.join('node_modules/pkg/index.js').to_s, reply[:absPath]
    end

    it 'resolves an app url path' do
      reply = request('resolve', path: '/lib/foo.js')

      assert reply[:ok]
      assert_equal '/lib/foo.js', reply[:urlPath]
    end

    it 'resolves an absolute file system path inside the app' do
      reply = request('resolve', path: Rails.root.join('lib/foo.js').to_s)

      assert reply[:ok]
      assert_equal '/lib/foo.js', reply[:urlPath]
    end

    it 'resolves a file inside a bundled gem to its virtual path' do
      gem_file = Proscenium.root.join('lib/proscenium/react-manager/react.js').to_s
      reply = request('resolve', path: gem_file)

      assert reply[:ok]
      assert_equal '/node_modules/@rubygems/proscenium/react-manager/react.js', reply[:urlPath]
    end

    it 'reports an unresolvable specifier as a protocol error' do
      reply = request('resolve', path: 'no-such-package-anywhere')

      refute reply[:ok]
      assert_match(/ResolveError/, reply[:error])
    end

    it 'rejects a relative specifier, which has no importer here' do
      reply = request('resolve', path: './foo.js')

      refute reply[:ok]
      assert_match(/ArgumentError/, reply[:error])
    end
  end

  describe 'build' do
    # Parity: an app module is whatever the app serves, byte for byte. Nothing about how it is
    # built is decided by the daemon.
    it 'returns exactly what rails serves' do
      reply = request('build', path: '/lib/import_absolute_module.js')

      assert reply[:ok]
      assert_equal served('/lib/import_absolute_module.js'), reply[:code]
    end

    it 'reports the imports it still contains, already resolved' do
      reply = unbundled { request('build', path: '/lib/import_absolute_module.js') }

      # Unbundled, so the import survives - and minified, because that is what the app serves in
      # this environment. The binding is renamed; the specifier is not.
      assert_includes reply[:code], '"/lib/foo4.js"'
      assert_equal Rails.root.join('lib/foo4.js').to_s,
                   reply[:imports]['/lib/foo4.js'][:absPath]
    end

    # The entry point is the exception - no browser asks for a test file, so it is built rather
    # than served. It still uses the app's own build settings, because bundling inlines app code
    # into it; only the runtime's own modules are added as external.
    it 'builds a path the app does not serve' do
      reply = request('build', path: '/test/js/resolution.test.js')

      assert reply[:ok]
      assert_includes reply[:code], 'bun:test'
    end

    # Serving writes to public/assets exactly as a browser request does - that is parity, and
    # code splitting depends on it. Only the entry point, which no browser requests, is unwritten.
    it 'does not write output for the entry point' do
      output = Rails.root.join('public/assets')
      FileUtils.rm_rf output

      request('build', path: '/test/js/resolution.test.js')

      assert_empty Dir.exist?(output) ? Dir.children(output) : []
    end

    it 'turns a build failure into a protocol error naming the file' do
      reply = request('build', path: '/lib/includes_error.js')

      refute reply[:ok]
      assert_match(/BuildError/, reply[:error])
      assert_match(/includes_error\.js/, reply[:error])
    end

    it 'serves a repeated build from cache' do
      first = request('build', path: '/lib/foo.js')
      second = request('build', path: '/lib/foo.js')

      assert_equal first[:code], second[:code]
      assert_same first[:code], second[:code]
    end

    it 'invalidates the cache when the file changes' do
      path = Rails.root.join('tmp/cache_probe.js')
      FileUtils.mkdir_p path.dirname

      begin
        path.write("console.log(1)\n")
        first = request('build', path: '/tmp/cache_probe.js')

        # mtime has one-second granularity on some filesystems, so set it explicitly rather than
        # sleeping.
        path.write("console.log(2)\n")
        File.utime(Time.now + 2, Time.now + 2, path)
        second = request('build', path: '/tmp/cache_probe.js')

        assert_includes first[:code], 'console.log(1)'
        assert_includes second[:code], 'console.log(2)'
      ensure
        FileUtils.rm_f path
      end
    end
  end

  describe 'rjs' do
    it 'renders server side javascript through the app routes' do
      reply = request('build', path: '/constants.rjs')

      assert_nil reply[:error]
      assert reply[:ok]
      assert_includes reply[:code], 'export const GREETING = "hello";'
    end

    it 'preserves the query string' do
      reply = request('build', path: '/constants.rjs?greeting=bonjour')

      assert_nil reply[:error]
      assert reply[:ok]
      assert_includes reply[:code], 'export const GREETING = "bonjour";'
    end

    # With `show_exceptions` off (the test default) Rails raises rather than returning an error
    # page, and the raised message is more useful than the guard's. Either way the runtime never
    # receives HTML to parse as JavaScript.
    # A path the app does not serve is reported when it is resolved, which is when the plugin
    # asks about it - before anything tries to load it.
    it 'refuses to resolve a module the app does not serve' do
      reply = request('build', path: '/lib/bun_fixtures/rjs.js')

      assert reply[:ok]
      assert reply[:imports].key?('/constants.rjs')

      # Materialised under tmp/, because a route-rendered module has no file of its own.
      assert reply[:imports]['/constants.rjs'][:materialised]
    end

    it 'refuses a route that raises' do
      reply = request('build', path: '/boom.rjs')

      refute reply[:ok]
      assert_match(/rjs blew up|returned 500/, reply[:error])
    end

    it 'refuses a route that does not return javascript' do
      reply = request('build', path: '/include_assets')

      refute reply[:ok]
      assert_match(/expected one of/, reply[:error])
    end
  end

  # Parity is the contract: a module the runtime imports is the module the browser gets. These are
  # the assertions that fail if the daemon ever starts deciding build settings for itself.
  describe 'parity with what rails serves' do
    it 'serves an app module byte for byte' do
      %w[/lib/foo.js /lib/import_absolute_module.js /lib/import_css_module.js].each do |path|
        assert_equal served(path), request('build', path: path)[:code], path
      end
    end

    # The one that bites. Minification decides the *shape* of a CSS module class name
    # (internal/plugin/css.go appends a path-derived suffix when identifiers are not minified), so
    # a daemon that forced `Minify: false` would hand tests class names the app never emits.
    it 'exposes the same css module class names as the css_module helper' do
      expected = Proscenium::CssModule::Transformer.class_names('/lib/styles', :@myClass).first
      digest = expected.delete_prefix('myClass')

      code = request('build', path: '/lib/import_css_module.js')[:code]

      assert_includes code, digest
      refute_includes code, "#{digest}_lib-styles-module"
    end

    it 'follows the app\'s own bundle setting' do
      path = '/lib/import_absolute_module.js'

      bundled = request('build', path: path)[:code]

      # A fresh server, because the cache is keyed on path and mtime - neither of which changes
      # when the app's configuration does.
      unbundled = unbundled do
        Proscenium::Runtime::Server.new(watch: nil)
                                   .handle('id' => 1, 'op' => 'build', 'path' => path)[:code]
      end

      # Bundled inlines the dependency, so no import survives. Unbundled keeps it. The bare
      # string is in both - it is what foo4.js logs - so the import statement is the discriminator.
      import_of_foo4 = %r{import[^;]*"/lib/foo4\.js"}

      refute_match import_of_foo4, bundled
      assert_match import_of_foo4, unbundled
    end

    it 'renders rjs through the app route, unaltered' do
      assert_equal served('/constants.rjs'), request('build', path: '/constants.rjs')[:code]
    end
  end

  describe 'unknown op' do
    it 'is a protocol error, not a crash' do
      reply = request('nonsense')

      refute reply[:ok]
      assert_match(/unknown op "nonsense"/, reply[:error])
      assert_equal 1, reply[:id]
    end
  end

  describe 'materialised modules' do
    let(:dir) { Rails.root.join('tmp/proscenium/served') }

    it 'writes a module the app renders but has no file for' do
      reply = request('build', path: '/lib/bun_fixtures/rjs.js')

      assert reply[:ok]
      assert reply[:imports]['/constants.rjs'][:materialised]
      assert_includes File.read(reply[:imports]['/constants.rjs'][:absPath]),
                      'export const GREETING'
    end

    it 'clears them' do
      request('build', path: '/lib/bun_fixtures/rjs.js')

      assert_predicate dir, :exist?
      refute_empty dir.children

      server.clear_materialised

      refute_predicate dir, :exist?
    end
  end

  describe 'over a socket' do
    it 'announces its socket path, then answers framed requests' do
      out = StringIO.new
      srv = Proscenium::Runtime::Server.new(stdout: out, watch: nil, threads: 2)

      # Left behind by a previous run. Starting up clears it. Written before the server starts,
      # not after: `start` clears the directory well before it announces, so a write racing that
      # clear survives it and the refutation below fails perhaps one run in four.
      stale = Rails.root.join('tmp/proscenium/served/stale.js')
      FileUtils.mkdir_p stale.dirname
      stale.write "export default 'stale';\n"

      thread = Thread.new { srv.start }

      begin
        wait_until { !out.string.empty? }
        refute_predicate stale, :exist?
        socket_path = out.string.lines.first.chomp
        assert_equal srv.socket_path, socket_path

        client = UNIXSocket.new(socket_path)

        # Two requests in one write, and a third split mid-line, to exercise reassembly.
        client.write(%({"id":1,"op":"handshake"}\n{"id":2,"op":"resolve","path":"/lib/foo.js"}\n))
        client.write(%({"id":3,"op":"buil))
        client.write(%(d","path":"/lib/foo.js"}\n))

        replies = Array.new(3) { JSON.parse(client.gets) }.index_by { |r| r['id'] }

        assert replies[1]['ok']
        assert_equal '/lib/foo.js', replies[2]['urlPath']
        assert_includes replies[3]['code'], 'console.log("/lib/foo.js")'
      ensure
        client&.close
        srv.handle({ 'id' => 99, 'op' => 'shutdown' })
        thread.join(2)
      end
    end
  end

  private

  # What a browser would get for this path, through the same middleware stack.
  def served(path)
    status, _headers, body = Rails.application.call(Rack::MockRequest.env_for(path))

    raise "#{path} returned #{status}" unless status == 200

    content = +''
    body.each { |chunk| content << chunk }
    content
  ensure
    body.close if body.respond_to?(:close)
  end

  # Runs a block with the app configured not to bundle, so unbundled parity can be asserted too.
  def unbundled
    was = Proscenium.config.bundle
    Proscenium.config.bundle = false
    yield
  ensure
    Proscenium.config.bundle = was
  end

  def wait_until(timeout: 5)
    deadline = Time.now + timeout
    sleep 0.01 until yield || Time.now > deadline
    raise 'timed out waiting for the server' unless yield
  end
end
