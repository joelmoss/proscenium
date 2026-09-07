# frozen_string_literal: true

require 'digest'
require 'securerandom'
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
    #       ├── spawn ─────────────────────────▶  boots Rails, then listens. Prints the socket
    #       │                                  │  path to stdout only when it chose the path
    #       │                                  │  itself; a caller that supplies one is told
    #       │                                  │  nothing, because it already knows.
    #       ├── connect(socket) ───────────────▶  UNIXServer
    #       │                                  │
    #       ├── {"id":1,"op":"handshake"} ─────▶  pool ──▶ config + pluginPath
    #       ├── {"id":2,"op":"resolve",...} ───▶  pool ──▶ Resolver.resolve
    #       ├── {"id":3,"op":"build",...} ─────▶  pool ──▶ Rails.application.call, or the
    #       │                                  │           builder for the entry point
    #       └── {"id":4,"op":"shutdown"} ──────▶  pool ──▶ closes the listener
    #
    # There is no `rjs` op: a `.rjs` path is fetched by `build` like anything else, and happens to
    # be answered by the app's own route.
    #
    # Why a socket rather than stdio: `rails runner CODE` boots the whole application before
    # evaluating CODE, so anything an initializer or a gem prints to stdout is already on the wire
    # before this class runs. A socket cannot be written to by accident.
    class Server
      # Modules the runtime provides itself, added to `External` for the entry-point build only.
      # See `build_entry` for why.
      RUNTIME_MODULES = ['bun:*', 'node:*'].freeze

      # What a module may come back as. A source map is JSON; everything else a JavaScript runtime
      # can import is JavaScript. Anything else - an HTML error page, most usefully - is refused
      # rather than handed to the runtime to choke on.
      CONTENT_TYPES = {
        '.map' => ['application/json'],
        '.css' => ['text/css'],
        :default => ['application/javascript', 'text/javascript']
      }.freeze

      # `import "/x.js"`, `import y from "/x.js"`, `export * from "/x.js"`, `import("/x.js")` and
      # `require("/x.js")`, with or without the whitespace a minifier removes.
      #
      # The lookbehind is what keeps `Array.from("/x.json")` and `Buffer.from("/x.json")` out. A
      # word boundary is not enough: `.` is a non-word character, so `\bfrom` matches the `from` in
      # any `<expr>.from(` call - and every match costs a full `Rails.application.call`, which is
      # exactly the spurious dispatch this regex exists to prevent.
      IMPORT_SPECIFIER = %r{(?<![.$\w])(?:from|import|require)\s*\(?\s*["'](/[^"'\s]+\.\w+)["']}

      # The socket's name inside its directory. Fixed, so a client that made the directory can name
      # the path without being told it.
      SOCKET_NAME = 'd.sock'

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

      # @param socket_dir [String] a private directory to put the socket in. Supplying one also
      #   suppresses the announcement, since the caller can name `SOCKET_NAME` inside it itself.
      #   Defaults to one this class creates. Either way it is removed on shutdown.
      # @param threads [Integer] size of the worker pool.
      # @param stdout [IO] where the socket path is announced.
      # @param watch [IO, nil] closing this stream shuts the server down. Defaults to $stdin, which
      #   the parent process holds open, so the server cannot outlive the test run. Ignored when
      #   parent_pid is given.
      # @param parent_pid [Integer, nil] poll this process instead of watching a stream, and shut
      #   down once it is gone. For a parent that cannot hold a pipe open - see `watch_parent`.
      def initialize(socket_dir: nil, threads: 4, stdout: $stdout, watch: $stdin, parent_pid: nil)
        # Nothing to announce when the caller supplied the directory - it can name the socket
        # itself, and this process' stdout is the terminal in that case.
        @announce = socket_dir.nil?
        @socket_dir = socket_dir
        @threads = threads
        @stdout = stdout
        @watch = parent_pid ? nil : watch
        @parent_pid = parent_pid
        @requests = Queue.new
        @cache = {}
        @key_mutexes = {}
        @cache_mutex = Mutex.new
        @resolve_mutex = Mutex.new
        @shutdown = false
      end

      # A socket inside a private directory rather than a predictable name in a shared one. The
      # old default was `proscenium-<pid>.sock` in Dir.tmpdir: a name anyone on the machine can
      # guess from `ps`, in a directory anyone can write to, and this daemon answers `build` with
      # code the client executes. `mktmpdir` is 0700 and its create is exclusive, so there is
      # nobody else in the directory to race. `/tmp` explicitly, not Dir.tmpdir, because a unix
      # socket path is capped near 104 bytes and a CI or sandboxed TMPDIR can spend most of it.
      #
      # Resolved on first use rather than in the constructor, because `handle` can be driven
      # without ever binding anything - most of this class' own tests do - and a constructor that
      # creates a directory would leave one behind for every such instance.
      def socket_path
        @socket_path ||= File.join(@socket_dir ||= Dir.mktmpdir('proscenium-', '/tmp'), SOCKET_NAME)
      end

      def start
        # Captured first and put back in the ensure below, because the write further down is to
        # process-wide config. A real daemon is spawned per test run and exits, so restoring it
        # there changes nothing - but `start` is also called in-process by this class' own tests,
        # and a write left standing would decide the build settings of every test that happened
        # to run after them, under whatever order minitest picked.
        code_splitting_was = Proscenium.config.code_splitting

        # A precompiled manifest would make `Resolver.resolve` hand back digest URLs from
        # public/assets instead of resolving the source. Nothing reloads it after this.
        Proscenium::Manifest.reset!

        # Code splitting off for everything this daemon hands back, not just the entry point.
        # `build_entry` already passes `CodeSplitting: false` for the one module it builds
        # directly, but a module that comes from `serve` is built by the app's own middleware
        # under the app's own config - so an app whose test files sit under a path Proscenium
        # serves has its entry point built with splitting on, and a dynamic `import()` in it comes
        # back as `../_asset_chunks/<name>-$HASH$.js`. A browser resolves that specifier against
        # the request URL and Proscenium serves it; a client of this daemon resolves it against
        # the importing file's path on disk, where nothing exists. The app's config is right for
        # the app and wrong here.
        #
        # Set here rather than asked of each app, because it is a property of this transport: no
        # client of this daemon can resolve a chunk path, and an app that turned splitting off to
        # satisfy `bun test` would be turning it off for its system tests too, which drive a real
        # browser and should keep the chunked output production emits.
        #
        # The cost, named rather than called parity: a module containing a dynamic `import()` is
        # compiled differently here, not merely divided up differently. With splitting on the
        # `import()` stays a fetch of a chunk; with it off esbuild inlines the imported module
        # into the bundle and rewrites the call to `Promise.resolve().then(...)`. Every other
        # module is byte-identical, so the one thing `bun test` cannot cover is the fetch itself -
        # which is a system test's job anyway.
        Proscenium.config.code_splitting = false

        # One daemon per test run, so this clears materialised modules between runs - including
        # after a run that died without shutting down. Cleared at boot rather than at exit so the
        # files are still there to look at when a run fails.
        clear_materialised

        FileUtils.rm_f(socket_path)
        @server = UNIXServer.new(socket_path)

        workers = Array.new(@threads) { worker }
        watch_parent

        announce
        accept_loop

        # Tell the workers to stop BEFORE waiting for them. `shutdown!` pushes the sentinels, and
        # it only runs in the ensure below - so joining first meant every join timed out and a
        # shutdown took a second per worker longer than it needed to.
        stop_workers
        workers.each { |t| t.join(1) }
      ensure
        # `shutdown!` first: it is the cleanup that leaves something behind on disk if it is
        # skipped, and it swallows its own errors, so the restore below always runs.
        shutdown!
        Proscenium.config.code_splitting = code_splitting_was
      end

      # Answer one request. Public so it can be driven directly from a test without a socket.
      #
      # Never raises. The rescue reports on the `id` captured before the work started, rather than
      # reading it out of the request again: `42` and `null` are both valid JSON lines, so a
      # request is not necessarily a Hash, and re-reading `request['id']` in the rescue reproduced
      # the very error it was handling - which escaped, killed the worker thread, and then killed
      # the whole daemon when `Thread#join` re-raised it into `start`.
      #
      # @param request [Hash] with String keys. Anything else is answered, not raised on.
      # @return [Hash] the reply, always carrying `id` and `ok`.
      def handle(request)
        id = request.is_a?(Hash) ? request['id'] : nil

        unless request.is_a?(Hash)
          return { id: id, ok: false,
                   error: "ProtocolError: expected a JSON object, got #{request.class}" }
        end

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
        { id: id, ok: false, error: "#{e.class}: #{e.message}" }
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
      # same bundling, minification and externals a browser gets. Code splitting is the single
      # exception - `start` turns it off process-wide, because no client of this daemon can resolve
      # a chunk path; see there for the cost. Any other setting decided here would be a way for a
      # test to pass against something the app does not serve - and minification alone changes CSS
      # module class names, so "close enough" is not.
      #
      # Bun's resolve hook cannot await a promise, so a module's imports are resolved here too, in
      # the same round trip, and the plugin answers from a lookup table.
      def op_build(request)
        path = url_path!(request.fetch('path'))

        # The client decides whether it wants a map, because it is the one that would throw it
        # away. Without this, `register({ sourcemaps: false })` still paid for a base64 blob
        # bigger than the code itself: generated, JSON-encoded, pushed over the socket, cached,
        # and then stripped by the plugin.
        sourcemap = request.fetch('sourcemap', true) ? true : false

        cached(:build, path, sourcemap) do
          code = serve_or_build(path, sourcemap: sourcemap)

          # A source map has no imports to resolve, and the client discards the field, so scanning
          # it is work nobody reads.
          path.end_with?('.map') ? { code: code } : { code: code, imports: resolve_imports(code) }
        end
      end

      # Everything `build` is given has to be a url path - the thing a browser would put in a GET -
      # because two of the places it ends up do not anchor it themselves. `File.join(Rails.root,
      # spec)` keeps a `..` verbatim, and `build_entry` hands the path to esbuild, which resolves
      # it relative to the app root and will happily climb out; the `serve` path is the only one
      # that gets `Rack::Utils.clean_path_info` for free, via Middleware::Base. A traversal 404s
      # there and then lands in `build_entry`, so without this guard `/lib/../../../secrets.js`
      # reads and returns any file esbuild can load.
      #
      # A scheme is refused for a second reason: `Rack::MockRequest.env_for` accepts a full URL and
      # takes SERVER_NAME from it, so a caller could otherwise choose the host the app sees and
      # walk straight past `config.hosts`.
      #
      # `resolve` deliberately does NOT go through this - it is given absolute filesystem paths on
      # purpose, including ones outside the root, because that is where a gem or a `link:`ed
      # package lives.
      def url_path!(path)
        unless path.start_with?('/') && !path.start_with?('//') && !path.include?('://')
          raise ProtocolError, "#{path.inspect} is not a url path"
        end

        expanded = File.expand_path(path.delete_prefix('/'), Rails.root)
        unless expanded == Rails.root.to_s || expanded.start_with?("#{Rails.root}/")
          raise ProtocolError, "#{path.inspect} resolves outside the application root"
        end

        path
      end

      # Proscenium serves anything under its own path globs. A test file is not one of those - no
      # browser ever asks for it - so it is the one module built directly.
      def serve_or_build(path, sourcemap: true)
        serve(path) || build_entry(path, sourcemap: sourcemap)
      end

      # The entry point is the one module a browser never requests, so it is built rather than
      # served. Four departures, none of which changes a single byte of app code:
      #
      #   Write    - its output is read as a string and never served, so writing it is litter.
      #   External - `bun:test` and `node:*` come from the runtime. Without this the build fails to
      #              resolve them, since bundled mode treats an unresolvable bare import as an
      #              error rather than a warning.
      #   Splitting- with `Write: false` a shared chunk is never written anywhere, so a test file
      #              containing a dynamic `import()` would come back importing
      #              `../_asset_chunks/<name>-$HASH$.js` - a path with nothing behind it. `start`
      #              turns this off process-wide too; kept here because `handle` can be driven
      #              without ever calling `start`.
      #   Sourcemap- inlined, because a separate `.map` is a second full build of the same module,
      #              and the client only ever turns it into a data URL anyway. A browser wants the
      #              separate file it can fetch on demand; nothing here is a browser.
      #
      # Notably NOT minification. Bundling inlines app modules into this build, so unminified here
      # would mean unminified class names for every CSS module the test imports - names the app
      # never emits. Legible failures come from the inlined source map instead.
      def build_entry(path, sourcemap: true)
        external = Proscenium.config.external.to_a + RUNTIME_MODULES

        Proscenium::Builder.build_to_string(
          path.delete_prefix('/'),
          Write: false, External: external, CodeSplitting: false, SourcemapInline: sourcemap
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
      # skipped rather than failing the build: a genuinely broken import fails more clearly at
      # resolve time.
      #
      # Anchored on import syntax rather than on any quoted path-shaped string. An app constant
      # like "/api/v1/thing.json" is not an import, and treating it as one meant a full
      # `Rails.application.call` per data literal - which for a route with side effects is a
      # request the developer never wrote. Handles minified output too, where the space goes:
      # `from"/x.js"`.
      def resolve_imports(code)
        code.scan(IMPORT_SPECIFIER).flatten.uniq.each_with_object({}) do |spec, acc|
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
        # The same guard `op_build` gets, and for the same two reasons - this specifier came out
        # of a regex scan of built output, which includes every string literal in every bundled
        # dependency. `File.join(Rails.root, spec)` keeps a `..` verbatim, and `serve` would take
        # SERVER_NAME from a `//host/x.js` shape and walk past `config.hosts`.
        spec = url_path!(spec)

        return op_resolve('path' => spec) if File.exist?(File.join(Rails.root, spec))

        code = serve(spec)
        raise ProtocolError, "#{spec} is not served by this app" if code.nil?

        relative = File.join(MATERIALISED_DIR, "#{Digest::SHA1.hexdigest(spec)[0, 12]}.js")
        target = Rails.root.join(relative)
        FileUtils.mkdir_p(target.dirname)
        write_atomically(target, code)

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
        # SERVER_NAME explicitly: `env_for` defaults it to `example.org`, which `config.hosts`
        # permits in test (it is empty there) and refuses in development, where Rails installs an
        # allowlist of `.localhost`/`.test`. Without this, `register({ env: "development" })` -
        # a documented option - 403s on every single module.
        Rack::MockRequest.env_for(path, 'SERVER_NAME' => 'localhost')
      end

      # Written to a unique path and renamed, because rename is atomic within a filesystem. The
      # check-then-write this replaces could interleave between two workers materialising the same
      # module, and a reader could see a partly written file.
      def write_atomically(target, code)
        return if target.exist? && target.read == code

        temp = target.sub_ext(".#{SecureRandom.hex(8)}.tmp")
        temp.write(code)
        File.rename(temp, target)
      ensure
        temp&.delete if temp&.exist?
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
      # ponytail: the key covers the keyed file only, and a bundled build inlines its whole graph -
      # which is the default, so in `--watch` editing any module a test imports can serve the
      # previous bundle until the test file itself is touched. Unbundled it is narrower but still
      # real: a CSS module, an SVG and i18n data are inlined either way. `Metafile: true` is
      # already set in internal/builder/build.go, so keying on the newest mtime across the
      # metafile's inputs is the fix when this bites.
      # Held across the build, not just around the hash read, so N concurrent requests for the same
      # module build it once and the rest wait for that result. A single mutex around the whole
      # thing would serialise every build and defeat the worker pool, so the lock is per key.
      #
      # A path with nothing on disk to key on is not cached at all. `.rjs` is rendered by a route,
      # so its bytes depend on app code that can change; keying it on a nil mtime made the key a
      # constant and pinned the first render for the life of the daemon. That is invisible in a
      # one-shot run and wrong in a watching one - a suite passing against bytes the app no longer
      # produces. A route render is cheap next to a build, so it happens each time instead.
      def cached(kind, path, *extra)
        mtime = mtime_of(path)
        return yield if mtime.nil?

        key = [kind, path, mtime, *extra]
        prune(kind, path, mtime)

        hit = @cache_mutex.synchronize { @cache[key] }
        return hit if hit

        key_mutex = @cache_mutex.synchronize { @key_mutexes[key] ||= Mutex.new }

        key_mutex.synchronize do
          hit = @cache_mutex.synchronize { @cache[key] }
          next hit if hit

          value = yield
          @cache_mutex.synchronize { @cache[key] = value }
          value
        end
      end

      # An edited file gets a new key, and the old one would otherwise sit in both hashes for the
      # life of the daemon - so a long `--watch` session holds every historical build of every
      # module it ever saw. Dropping the superseded generations keeps one entry per module. Every
      # variant of a superseded mtime goes, whatever else is in its key.
      def prune(kind, path, mtime)
        @cache_mutex.synchronize do
          stale = @cache.keys.select { |k| k[0] == kind && k[1] == path && k[2] != mtime }
          stale.each { |k| @cache.delete(k) && @key_mutexes.delete(k) }
        end
      end

      # `path` is a url path, so its leading slash has to go before it can be joined - otherwise
      # Pathname#join treats it as absolute and stats the wrong file entirely.
      #
      # A source map is keyed on its source file: nothing is written under the `.map` name, but its
      # contents track the file it describes, which is the thing that changes.
      def mtime_of(path)
        target = path.delete_suffix('.map').delete_prefix('/')

        File.mtime(Rails.root.join(target)).to_f
      rescue SystemCallError
        nil
      end

      # A worker must not be able to die. `Thread#join` re-raises a dead thread's exception into
      # whoever joins it, and `start` joins every worker - so one unhandled error in here took the
      # entire daemon down mid-suite, not just the one request.
      def worker
        Thread.new do
          while (job = @requests.pop)
            socket, request, write_mutex = job
            answer(socket, write_mutex, handle(request))
          end
        end
      end

      # `JSON.generate` raises `JSON::GeneratorError` - a StandardError, not an IOError - when the
      # reply carries bytes that are not valid UTF-8, which is what a mis-encoded source file in
      # the app produces. That needs reporting as a failed build rather than taking the daemon
      # with it, so the developer learns which module is mis-encoded.
      def answer(socket, write_mutex, reply)
        line = begin
          JSON.generate(reply)
        rescue StandardError => e
          JSON.generate({ id: reply[:id], ok: false,
                          error: "#{e.class}: #{e.message} - the built output is not valid UTF-8" })
        end

        write_mutex.synchronize { socket.puts(line) }
      rescue IOError, Errno::EPIPE
        # The runner went away mid-request. Nothing to report it to.
        nil
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
      # a direct child of the process it watches, so when that process exits this one is reparented
      # and the pid stops resolving - which is the signal. A second of latency past the end of a
      # test run costs nothing.
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

        @stdout.puts(socket_path)
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
              # The stream is desynchronised, and a reply cannot help: every reply is matched to a
              # request by `id`, and a line that would not parse has none to echo. A client that
              # correlates on id drops an id-less reply and waits for a reply that never comes. So
              # close the connection instead - the client's close handler fails every request in
              # flight with a named error, which is a diagnosable end rather than a hang.
              report_unparseable(socket, write_mutex, e)

              return
            end
          end
        end
      rescue IOError, Errno::ECONNRESET
        nil
      ensure
        socket.close unless socket.closed?
      end

      # Best effort: the client is told why the connection is about to close, but it may already be
      # gone, and there is nowhere to report that.
      def report_unparseable(socket, write_mutex, error)
        write_mutex.synchronize do
          socket.puts(JSON.generate({ ok: false, error: "invalid JSON: #{error.message}" }))
        end
      rescue IOError, Errno::EPIPE
        nil
      end

      # A nil per worker: `Queue#pop` blocks, so a worker only notices a shutdown by being handed
      # one. Idempotent, because `shutdown!` runs on every exit path as well.
      def stop_workers
        @threads.times { @requests << nil }
      end

      def shutdown!
        @shutdown = true
        stop_workers
        @server&.close unless @server&.closed?
        # nil when `socket_path` raised before it could memoise - `mktmpdir` on a /tmp this
        # process cannot write to, most usefully. `rm_f(nil)` raises TypeError, which the rescue
        # below does not catch, so the useful error was replaced by a confusing one.
        FileUtils.rm_f(@socket_path) if @socket_path
        FileUtils.remove_entry(@socket_dir) if @socket_dir && Dir.exist?(@socket_dir)
      rescue SystemCallError, IOError
        nil
      end
    end
  end
end
