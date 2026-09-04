# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'socket'
require 'tmpdir'

module Proscenium
  module Runtime
    # A long-lived Rails process that answers build and resolve requests from a JavaScript test
    # runner. Launched by the runner's preload script, one per test run.
    #
    #   preload.js                      Server (this class)
    #       │                                  │
    #       ├── spawn ─────────────────────────▶  boots Rails, then prints ONE line to stdout:
    #       │                                  │  the socket path. Nothing else uses that channel.
    #       ├── connect(socket) ───────────────▶  UNIXServer
    #       │                                  │
    #       ├── {"id":1,"op":"handshake"} ─────▶  pool ──▶ config + pluginPath
    #       ├── {"id":2,"op":"resolve",...} ───▶  pool ──▶ Resolver.resolve
    #       ├── {"id":3,"op":"build",...} ─────▶  pool ──▶ Builder.build_to_string
    #       └── {"id":4,"op":"rjs",...} ───────▶  pool ──▶ Rails.application.call
    #
    # Why a socket rather than stdio: `rails runner CODE` boots the whole application before
    # evaluating CODE, so anything an initializer or a gem prints to stdout is already on the wire
    # before this class runs. A socket cannot be written to by accident.
    class Server
      # The entry point - a test file - is the one module a browser never requests, so it is the
      # one module built directly rather than served. Three departures, all of them about the test
      # runner rather than the app:
      #
      #   Minify  - a test file is not shipped, and a legible stack trace is worth more.
      #   Write   - its output is read as a string and never served, so writing it is litter.
      #   External- `bun:test` and `node:*` are provided by the runtime. Without this the build
      #             fails to resolve them, since bundled mode treats an unresolvable bare import as
      #             an error rather than a warning.
      RUNTIME_MODULES = ['bun:*', 'node:*'].freeze

      # What a module may come back as. A source map is JSON; everything else a JavaScript runtime
      # can import is JavaScript. Anything else - an HTML error page, most usefully - is refused
      # rather than handed to the runtime to choke on.
      CONTENT_TYPES = {
        '.map' => ['application/json'],
        :default => ['application/javascript', 'text/javascript']
      }.freeze

      # Where a module with no file of its own - `.rjs`, rendered by a route - is written, so the
      # test runner has a real path to import it from. Relative to Rails.root.
      MATERIALISED_DIR = 'tmp/proscenium/served'

      class ProtocolError < StandardError; end

      def self.start(**)
        new(**).start
      end

      # Removes every materialised module. Exposed because `handle` can be driven without ever
      # calling `start` - a test, or another runtime's adapter.
      def clear_materialised
        FileUtils.rm_rf(Rails.root.join(MATERIALISED_DIR))
      end

      # @param socket_path [String] where to listen. Defaults to a unique path under Dir.tmpdir.
      #   Supplying one also suppresses the announcement, since the caller already knows it.
      # @param threads [Integer] size of the worker pool.
      # @param stdout [IO] where the socket path is announced.
      # @param watch [IO, nil] closing this stream shuts the server down. Defaults to $stdin, which
      #   the parent process holds open, so the server cannot outlive the test run. Ignored when
      #   parent_pid is given.
      # @param parent_pid [Integer, nil] poll this process instead of watching a stream, and shut
      #   down once it is gone. For a parent that cannot hold a pipe open - see `watch_parent`.
      def initialize(socket_path: nil, threads: 4, stdout: $stdout, watch: $stdin, parent_pid: nil)
        # Nothing to announce when the caller chose the path - it already knows it, and this
        # process' stdout is the terminal in that case.
        @announce = socket_path.nil?
        @socket_path = socket_path || File.join(Dir.tmpdir, "proscenium-#{Process.pid}.sock")
        @threads = threads
        @stdout = stdout
        @watch = parent_pid ? nil : watch
        @parent_pid = parent_pid
        @requests = Queue.new
        @cache = {}
        @cache_mutex = Mutex.new
        @resolve_mutex = Mutex.new
        @shutdown = false
      end

      attr_reader :socket_path

      def start
        # A precompiled manifest would make `Resolver.resolve` hand back digest URLs from
        # public/assets instead of resolving the source. Nothing reloads it after this.
        Proscenium::Manifest.reset!

        # One daemon per test run, so this clears materialised modules between runs - including
        # after a run that died without shutting down. Cleared at boot rather than at exit so the
        # files are still there to look at when a run fails.
        clear_materialised

        FileUtils.rm_f(@socket_path)
        @server = UNIXServer.new(@socket_path)

        workers = Array.new(@threads) { worker }
        watch_parent

        announce
        accept_loop

        workers.each { |t| t.join(1) }
      ensure
        shutdown!
      end

      # Answer one request. Public so it can be driven directly from a test without a socket.
      #
      # @param request [Hash] with String keys.
      # @return [Hash] the reply, always carrying `id` and `ok`.
      def handle(request)
        id = request['id']
        op = request['op']

        reply = case op
                when 'handshake' then op_handshake
                when 'resolve' then op_resolve(request)
                when 'build' then op_build(request)
                when 'shutdown' then op_shutdown
                else raise ProtocolError, "unknown op #{op.inspect}"
                end

        { id: id, ok: true }.merge(reply)
      rescue StandardError => e
        { id: request['id'], ok: false, error: "#{e.class}: #{e.message}" }
      end

      private

      def op_handshake
        {
          config: {
            root: Rails.root.to_s,
            gemPath: Proscenium.root.to_s,
            pluginPath: File.expand_path('bun.js', __dir__),
            rubyGems: Proscenium::BundledGems.paths,
            aliases: Proscenium.config.aliases,
            environment: Rails.env.to_s
          }
        }
      end

      # Resolution is Ruby's job, in both directions. `Resolver.resolve` already knows the corners -
      # which paths belong to a bundled gem, which gem root a virtual `@rubygems/*` path maps to,
      # and that the `proscenium` gem's own root is a subdirectory - and reimplementing that in
      # JavaScript would be a third copy of the same rule.
      #
      # Returns everything the JS side needs from one round trip:
      #   urlPath - the browser-facing path, which is also the module's identity and what `build`
      #             is given
      #   absPath - the real file on disk, for the runtime's own resolver
      def op_resolve(request)
        path = request.fetch('path')

        # `Resolver.resolved` is a plain class-level Hash with no synchronisation, so concurrent
        # resolves would race on it. Resolution is cheap and memoised, so serialising it costs
        # little; the expensive work (build) stays parallel.
        _manifest, url_path, abs_path = @resolve_mutex.synchronize do
          Proscenium::Resolver.resolve(path, as_array: true)
        end

        { urlPath: url_path, absPath: abs_path }
      end

      # Returns the module exactly as Rails would serve it, together with every import inside it,
      # already resolved.
      #
      # The module is fetched through the middleware stack rather than rebuilt with settings of
      # this daemon's own choosing. That is what parity means: the same `Proscenium.config`, so the
      # same bundling, minification, code splitting and externals a browser gets. Any setting
      # decided here would be a way for a test to pass against something the app does not serve -
      # and minification alone changes CSS module class names, so "close enough" is not.
      #
      # Bun's resolve hook cannot await a promise, so a module's imports are resolved here too, in
      # the same round trip, and the plugin answers from a lookup table.
      def op_build(request)
        path = request.fetch('path')

        cached(:build, path) do
          code = serve_or_build(path)

          { code: code, imports: resolve_imports(code) }
        end
      end

      # Proscenium serves anything under its own path globs. A test file is not one of those - no
      # browser ever asks for it - so it is the one module built directly.
      def serve_or_build(path)
        serve(path) || build_entry(path)
      end

      # The entry point is the one module a browser never requests, so it is built rather than
      # served. Only two departures, and neither changes a single byte of app code:
      #
      #   Write    - its output is read as a string and never served, so writing it is litter.
      #   External - `bun:test` and `node:*` come from the runtime. Without this the build fails to
      #              resolve them, since bundled mode treats an unresolvable bare import as an
      #              error rather than a warning.
      #   Splitting- with `Write: false` a shared chunk is never written anywhere, so a test file
      #              containing a dynamic `import()` would come back importing
      #              `../_asset_chunks/<name>-$HASH$.js` - a path with nothing behind it.
      #
      # Notably NOT minification. Bundling inlines app modules into this build, so unminified here
      # would mean unminified class names for every CSS module the test imports - names the app
      # never emits. Legible failures come from the inlined source map instead.
      def build_entry(path)
        external = Proscenium.config.external.to_a + RUNTIME_MODULES

        Proscenium::Builder.build_to_string(
          path.delete_prefix('/'), Write: false, External: external, CodeSplitting: false
        )[:response]
      end

      # A GET through the full middleware stack, as a browser makes. Returns nil when Proscenium
      # does not serve this path, so the caller can fall back to building it.
      #
      # An unservable path does not necessarily 404: with `show_exceptions` off, which is the test
      # default, Rails raises instead. Either way it means "not ours".
      def serve(path)
        status, headers, body = Rails.application.call(rack_env_for(path))

        content = +''
        body.each { |chunk| content << chunk }

        return nil if status == 404

        guard_response!(path, status, headers, content)
      rescue ActionController::RoutingError
        nil
      ensure
        body.close if body.respond_to?(:close)
      end

      # Root-absolute, extension-bearing specifiers are what Proscenium emits, and the only thing
      # the plugin's `^/` filter will be asked about. A specifier that cannot be resolved is
      # skipped rather than failing the build: it may be a string literal that merely looks like a
      # path, and a genuinely broken import fails more clearly at resolve time.
      def resolve_imports(code)
        code.scan(%r{["'](/[^"'\s]+\.\w+)["']}).flatten.uniq.each_with_object({}) do |spec, acc|
          acc[spec] = resolution_for(spec)
        rescue StandardError
          next
        end
      end

      # Bun needs a real file for every import: a namespaced virtual module can only be imported
      # dynamically, and app code imports statically. Most specifiers already have one. Those that
      # do not - `.rjs`, rendered by a route - are written under `tmp/` exactly as served, without
      # being rebuilt, because unaltered is what the browser executes.
      def resolution_for(spec)
        return op_resolve('path' => spec) if File.exist?(File.join(Rails.root, spec))

        code = serve(spec)
        raise ProtocolError, "#{spec} is not served by this app" if code.nil?

        relative = File.join(MATERIALISED_DIR, "#{Digest::SHA1.hexdigest(spec)[0, 12]}.js")
        target = Rails.root.join(relative)
        FileUtils.mkdir_p(target.dirname)
        target.write(code) unless target.exist? && target.read == code

        { urlPath: spec, absPath: target.to_s, materialised: true }
      end

      # A plain GET, deliberately. Marking it XHR would silence
      # ActionController::InvalidCrossOriginRequest, but it also changes Rails' format negotiation -
      # a route that renders HTML to a browser renders JavaScript to an XHR - so the harness would
      # be testing a different response than production serves.
      #
      # A browser importing `/foo.rjs` from a module also issues a non-XHR GET returning
      # JavaScript, so an app serving `.rjs` already needs `skip_forgery_protection` on that
      # action. Leaving the request faithful means the developer sees that requirement here rather
      # than in production.
      def rack_env_for(path)
        Rack::MockRequest.env_for(path)
      end

      def op_shutdown
        @shutdown = true
        @server&.close
        {}
      end

      # A Rack response is always a response, even when it went wrong. Handing a 404's HTML error
      # page to a JavaScript runtime produces a parse error pointing at line 1 of the developer's
      # own file, which says nothing about the missing route that actually caused it.
      def guard_response!(path, status, headers, content)
        unless (200..299).cover?(status)
          raise ProtocolError, "#{path} returned #{status}\n#{content.truncate(2000)}"
        end

        expected = CONTENT_TYPES.fetch(File.extname(path), CONTENT_TYPES[:default])
        type = headers.find { |k, _| k.to_s.downcase == 'content-type' }&.last.to_s

        unless expected.any? { |t| type.start_with?(t) }
          raise ProtocolError,
                "#{path} returned content type #{type.inspect}, expected one of #{expected.inspect}"
        end

        content
      end

      # Keyed on the source file's mtime so an edit is picked up between runs of a watching runner.
      #
      # ponytail: the key covers the entry file only. Unbundled output inlines a CSS module, an SVG
      # or i18n data, so editing one of those without touching the importing module can serve a
      # stale build in watch mode. Track the build's own inputs (esbuild's metafile) if that bites.
      def cached(kind, path)
        key = [kind, path, mtime_of(path)]

        hit = @cache_mutex.synchronize { @cache[key] }
        return hit if hit

        value = yield
        @cache_mutex.synchronize { @cache[key] = value }
        value
      end

      # `path` is a url path, so its leading slash has to go before it can be joined - otherwise
      # Pathname#join treats it as absolute and stats the wrong file entirely.
      def mtime_of(path)
        File.mtime(Rails.root.join(path.delete_prefix('/'))).to_f
      rescue SystemCallError
        nil
      end

      def worker
        Thread.new do
          while (job = @requests.pop)
            socket, request, write_mutex = job
            reply = handle(request)

            begin
              write_mutex.synchronize { socket.puts(JSON.generate(reply)) }
            rescue IOError, Errno::EPIPE
              # The runner went away mid-request. Nothing to report it to.
            end
          end
        end
      end

      # The run is over when the parent is gone - cleanly or otherwise - and this process must not
      # survive it.
      #
      # Two ways to notice, because one of them is unavailable to a Bun test runner. The stream
      # watch is the better signal: the parent holds $stdin open for the life of the run, so EOF
      # arrives the moment it exits. But under `bun test`, once happy-dom's GlobalRegistrator has
      # run and a DOM-touching package has been imported, every pipe Bun opens to a child is
      # broken from the start - the child sees immediate EOF on stdin and the parent captures no
      # stdout - so a runner in that position passes `parent_pid` and this polls instead.
      def watch_parent
        return watch_parent_pid if @parent_pid
        return unless @watch

        Thread.new do
          @watch.read
        rescue IOError
          nil
        ensure
          op_shutdown
        end
      end

      # `kill(0)` signals nothing; it just asks whether the process is still there. This daemon is
      # not the parent's child, so there is no reaping to confuse it - the pid is either live or
      # gone. A second of latency past the end of a test run costs nothing.
      #
      # ESRCH only, deliberately: EPERM means the process is alive and merely belongs to someone
      # else, which cannot happen for a parent that spawned this one, and treating it as death
      # would shut down a running test suite.
      def watch_parent_pid
        Thread.new do
          loop do
            sleep 1

            begin
              Process.kill(0, @parent_pid)
            rescue Errno::ESRCH
              break
            end
          end

          op_shutdown
        end
      end

      def announce
        return unless @announce

        @stdout.puts(@socket_path)
        @stdout.flush
      end

      def accept_loop
        until @shutdown
          begin
            socket = @server.accept
          rescue IOError, Errno::EBADF
            break
          end

          Thread.new { read_requests(socket) }
        end
      end

      # Reads newline-framed JSON. A line can arrive split across reads, so partial input is held
      # in a buffer until its terminator shows up.
      def read_requests(socket)
        write_mutex = Mutex.new
        buffer = +''

        while (chunk = socket.readpartial(16_384))
          buffer << chunk

          while (newline = buffer.index("\n"))
            line = buffer.slice!(0..newline).chomp
            next if line.empty?

            begin
              @requests << [socket, JSON.parse(line), write_mutex]
            rescue JSON::ParserError => e
              write_mutex.synchronize do
                socket.puts(JSON.generate({ ok: false, error: "invalid JSON: #{e.message}" }))
              end
            end
          end
        end
      rescue IOError, Errno::ECONNRESET
        nil
      ensure
        socket.close unless socket.closed?
      end

      def shutdown!
        @shutdown = true
        @threads.times { @requests << nil }
        @server&.close unless @server&.closed?
        FileUtils.rm_f(@socket_path)
      rescue SystemCallError, IOError
        nil
      end
    end
  end
end
