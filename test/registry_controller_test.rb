# frozen_string_literal: true

require 'test_helper'

class Proscenium::RegistryControllerTest < ActiveSupport::TestCase
  attr_reader :response

  let(:gem1_version) { Bundler.load.specs['gem1'].first.version.to_s }
  let(:tarball_mtime) { Proscenium::RegistryController::TARBALL_MTIME }

  # The engine is a Rack app in its own right, so it is called directly rather than mounted into
  # the dummy app.
  def get(path)
    @response = Rack::MockRequest.new(Proscenium::Railtie).get("/registry/#{path}")
  end

  def json = JSON.parse(response.body)
  def dist = json.dig('versions', gem1_version, 'dist')

  # Fetches the tarball the last packument advertised, and returns its bytes.
  def fetch_tarball(url = dist['tarball'])
    @response = Rack::MockRequest.new(Proscenium::Railtie).get(URI(url).path)
    assert_equal 200, response.status
    response.body.b
  end

  # The bytes of package/package.json inside a tarball.
  def packed(tarball)
    Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(tarball))).each do |entry|
      break entry.read if entry.full_name == 'package/package.json'
    end
  end

  def packed_package_json(tarball) = JSON.parse(packed(tarball).force_encoding(Encoding::UTF_8))

  # Points one gem at another directory for the block. Plain singleton surgery, as this suite does
  # not load Minitest::Mock.
  def with_gem_path(name, path)
    original = Proscenium::BundledGems.method(:pathname_for)
    Proscenium::BundledGems.define_singleton_method(:pathname_for) do |n|
      n == name ? Pathname(path) : original.call(n)
    end
    yield
  ensure
    Proscenium::BundledGems.define_singleton_method(:pathname_for, original)
  end

  # A gem1 whose package.json holds these bytes, for the block.
  def with_package_json(contents)
    Dir.mktmpdir do |dir|
      File.binwrite File.join(dir, 'package.json'), contents
      with_gem_path('gem1', dir) { yield dir }
    end
  end

  it 'serves an installed gem at its installed version' do
    get '@rubygems/gem1'

    assert_equal 200, response.status
    assert_equal '@rubygems/gem1', json['name']
    assert_equal gem1_version, json.dig('dist-tags', 'latest')
    assert_equal %w[open-props string-length],
                 json.dig('versions', gem1_version, 'dependencies').keys.sort
    assert_equal "http://example.org/registry/@rubygems/gem1/-/gem1-#{gem1_version}.tgz",
                 dist['tarball']
  end

  it 'advertises the digests of the tarball it serves' do
    get '@rubygems/gem1'
    integrity, shasum = dist.values_at('integrity', 'shasum')
    tarball = fetch_tarball

    assert_equal "sha512-#{Digest::SHA512.base64digest(tarball)}", integrity
    assert_equal Digest::SHA1.hexdigest(tarball), shasum
  end

  # `npm ci` and a frozen pnpm install fetch the URL in the lockfile, and never the packument.
  it 'serves a tarball that no packument was asked for first' do
    tarball = fetch_tarball("/registry/@rubygems/gem1/-/gem1-#{gem1_version}.tgz")

    assert_equal 'application/octet-stream', response.content_type
    assert_equal %w[open-props string-length],
                 packed_package_json(tarball)['dependencies'].keys.sort
  end

  it 'answers 404 for the tarball of a version that is not the installed one' do
    get '@rubygems/gem1/-/gem1-99.9.9.tgz'

    assert_equal 404, response.status
    assert_match(/99\.9\.9/, json['error'])
  end

  # Only npm's own file name; anything else naming the version is not a URL this registry gave out.
  %w[0.1.0.tgz gem1-0.1.0 0.1.0].each do |file|
    it "answers 404 for a tarball named #{file}" do
      get "@rubygems/gem1/-/#{file}"

      # The controller's own answer, not a route that did not match.
      assert_equal 404, response.status
      assert_match(/has no version/, json['error'])
    end
  end

  # The URL a lockfile records must carry the path the engine is mounted at.
  it 'advertises the tarball under the path the engine is mounted at' do
    @response = Rack::MockRequest.new(Proscenium::Railtie)
                                 .get('/registry/@rubygems/gem1', 'SCRIPT_NAME' => '/proscenium')

    assert_equal "http://example.org/proscenium/registry/@rubygems/gem1/-/gem1-#{gem1_version}.tgz",
                 dist['tarball']
  end

  # npm and pnpm retry a 5xx, so an unreadable package.json is a 422 like an invalid one.
  it 'answers 422 for a package.json that cannot be read' do
    Dir.mktmpdir do |dir|
      Dir.mkdir File.join(dir, 'package.json')
      with_gem_path('gem1', dir) { get '@rubygems/gem1' }

      assert_equal 422, response.status
      assert_match(%r{`@rubygems/gem1` has an invalid package\.json}, json['error'])
      refute_includes json['error'], dir
    end
  end

  # Only a gem that has no package.json gets a generated one. A gem whose directory has gone, or
  # whose package.json cannot be followed, is broken, and a generated one would hide that.
  it 'answers 422 for a gem whose directory has gone' do
    dir = Dir.mktmpdir
    FileUtils.rm_rf dir
    with_gem_path('gem1', dir) { get '@rubygems/gem1' }

    assert_equal 422, response.status
    assert_match(/cannot be read/, json['error'])
  end

  it 'answers 422 for a package.json that is a broken symlink' do
    skip 'Creating a symlink needs privileges on Windows' if Gem.win_platform?

    Dir.mktmpdir do |dir|
      File.symlink File.join(dir, 'missing.json'), File.join(dir, 'package.json')
      with_gem_path('gem1', dir) { get '@rubygems/gem1' }

      assert_equal 422, response.status
      assert_match(/cannot be read/, json['error'])
    end
  end

  it 'advertises no dependencies for a package.json without any' do
    with_package_json({ 'name' => '@rubygems/gem1' }.to_json) do
      get '@rubygems/gem1'

      assert_equal 200, response.status
      assert_equal({}, json.dig('versions', gem1_version, 'dependencies'))
    end
  end

  it 'answers 404 for the tarball of a gem that is not in the bundle' do
    get '@rubygems/not_a_gem/-/not_a_gem-1.0.0.tgz'

    assert_equal 404, response.status
    assert_match(/not_a_gem/, json['error'])
  end

  # A lockfile records the integrity, so every build must produce the same bytes.
  it 'serves the same tarball every time' do
    get '@rubygems/gem1'
    url = dist['tarball']

    assert_equal fetch_tarball(url), fetch_tarball(url)
  end

  # RubyGems before 3.6.7 makes its epoch the time each process starts, and SOURCE_DATE_EPOCH
  # overrides it on any version, so a tarball stamped with it changes on every restart.
  it 'builds the same tarball whatever epoch RubyGems reports' do
    original = Gem.method(:source_date_epoch)
    integrities = [1, 2_000_000_000].map do |epoch|
      Gem.define_singleton_method(:source_date_epoch) { Time.at(epoch).utc }
      get '@rubygems/gem1'
      dist['integrity']
    end

    assert_equal 1, integrities.uniq.size
  ensure
    Gem.define_singleton_method(:source_date_epoch, original)
  end

  it 'stamps the tarball with a fixed time' do
    get '@rubygems/gem1'
    tarball = fetch_tarball

    Zlib::GzipReader.wrap(StringIO.new(tarball)) do |gz|
      assert_equal tarball_mtime, gz.mtime.to_i
      assert_equal([tarball_mtime], Gem::Package::TarReader.new(gz).map { it.header.mtime })
    end
  end

  # The tar entry is framed by hand: padded to a whole 512 byte block, then two empty blocks.
  [300, 512, 1500].each do |size|
    it "frames a #{size} byte package.json as a whole tar archive" do
      package = { 'dependencies' => {}, 'pad' => '' }
      package['pad'] = 'x' * (size - package.to_json.bytesize)

      with_package_json(package.to_json) do
        get '@rubygems/gem1'
        tar = Zlib::GzipReader.new(StringIO.new(fetch_tarball)).read.b

        assert_equal 0, tar.bytesize % 512
        assert_equal "\0" * 1024, tar[-1024..]
        entries = Gem::Package::TarReader.new(StringIO.new(tar)).map { [it.full_name, it.read] }
        assert_equal [['package/package.json', package.to_json]], entries
      end
    end
  end

  # Not reformatted: an encoder's escaping or number format would change the bytes, and with them
  # the integrity every lockfile records.
  it "packs the gem's own package.json, byte for byte" do
    contents = %({\n  "description": "<b> & \\u00e9",\n  "dependencies": { "a": ">=1.0" }\n}\n)

    with_package_json(contents) do
      get '@rubygems/gem1'

      assert_equal contents.b, packed(fetch_tarball)
    end
  end

  it 'serves the package.json as it is now, after it changes' do
    Dir.mktmpdir do |dir|
      package_json = File.join(dir, 'package.json')
      with_gem_path('gem1', dir) do
        File.write package_json, { dependencies: { 'a' => '1' } }.to_json
        get '@rubygems/gem1'
        earlier = dist['integrity']

        File.write package_json, { dependencies: { 'b' => '1' } }.to_json
        get '@rubygems/gem1'

        refute_equal earlier, dist['integrity']
        assert_equal({ 'b' => '1' }, packed_package_json(fetch_tarball)['dependencies'])
      end
    end
  end

  {
    'not JSON' => '{', 'empty' => '', 'not an object' => '[]', 'null' => 'null',
    # Parse, but cannot be generated again.
    'holding a number too big for JSON' => '{"a":1e400}',
    # Ruby's parser takes these by default, but npm does not.
    'holding a block comment' => '{/* c */"a":1}',
    'holding a line comment' => %({"a":1 // c\n}),
    'not UTF-8' => "{\"a\":\"\xFF\"}".b,
    # The parser's message quotes these bytes, so the reason must be scrubbed to render as JSON.
    'UTF-16' => "\xFF\xFE{\0}\0".b
  }.each do |what, contents|
    it "answers 422 naming the package for a package.json that is #{what}" do
      with_package_json(contents) do |dir|
        get '@rubygems/gem1'

        assert_equal 422, response.status
        assert_match(%r{`@rubygems/gem1` has an invalid package\.json}, json['error'])
        refute_includes json['error'], dir
      end
    end
  end

  it 'answers 422 for the tarball of a gem whose package.json is invalid' do
    with_package_json('{') do
      get "@rubygems/gem1/-/gem1-#{gem1_version}.tgz"

      assert_equal 422, response.status
      assert_match(/invalid package\.json/, json['error'])
    end
  end

  # npm strips a byte order mark, which some Windows editors write.
  it 'reads a package.json that starts with a byte order mark' do
    with_package_json("\uFEFF#{{ dependencies: { 'a' => '1' } }.to_json}") do
      get '@rubygems/gem1'

      assert_equal 200, response.status
      assert_equal({ 'a' => '1' }, packed_package_json(fetch_tarball)['dependencies'])
    end
  end

  it 'serves an installed gem when its installed version is requested' do
    get "@rubygems/gem1/#{gem1_version}"

    assert_equal 200, response.status
    assert_equal gem1_version, json.dig('dist-tags', 'latest')
  end

  # `latest` is the one dist-tag the packument advertises, and npm resolves it at this URL.
  it 'serves an installed gem when its latest version is requested' do
    get '@rubygems/gem1/latest'

    assert_equal 200, response.status
    assert_equal gem1_version, json.dig('dist-tags', 'latest')
  end

  it 'answers 404 for a version that is not the installed one' do
    get '@rubygems/gem1/99.9.9'

    assert_equal 404, response.status
    assert_match(/99\.9\.9/, json['error'])
  end

  it 'answers 404 for a gem that is not in the bundle' do
    get '@rubygems/not_a_gem'

    assert_equal 404, response.status
    assert_match(/not_a_gem/, json['error'])
  end

  # How npm itself asks for a scoped package's metadata.
  it 'answers 404 for a gem that is not in the bundle, with its scope URL-encoded' do
    get '@rubygems%2fnot_a_gem'

    assert_equal 404, response.status
    assert_match(/not_a_gem/, json['error'])
  end

  it 'answers 404 for a gem that is not in the bundle, with a version' do
    get '@rubygems/not_a_gem/1.0.0'

    assert_equal 404, response.status
    assert_match(/not_a_gem/, json['error'])
  end

  # Bundler is in every lockfile, but BundledGems leaves it out, so it is not served.
  it 'answers 404 for bundler' do
    get '@rubygems/bundler'

    assert_equal 404, response.status
    assert_match(/bundler/, json['error'])
  end

  # A newline (%0A) must not let a malformed name through: the pattern matches the whole string,
  # not one line of it.
  ['@other/gem1', '@rubygems/ge!m1', 'junk%0A@rubygems/gem1', '@rubygems/gem1%0Ajunk'].each do |pkg|
    it "answers 404 for an invalid package name: #{pkg}" do
      get pkg

      assert_equal 404, response.status
      assert_match(/not valid/, json['error'])
    end
  end

  it 'generates a package.json for a gem without one' do
    Dir.mktmpdir do |dir|
      with_gem_path('gem1', dir) do
        get '@rubygems/gem1'

        assert_equal 200, response.status
        assert_empty json.dig('versions', gem1_version, 'dependencies')
        package = packed_package_json(fetch_tarball)
        assert_equal gem1_version, package['version']
        assert_empty package['dependencies']
      end
    end
  end

  # A tar entry's size is in bytes. Sized in characters, a package.json with any non-ASCII text
  # overflows its entry.
  it 'packs a package.json with non-ASCII text' do
    package = { 'name' => '@rubygems/gem1', 'description' => 'Café ☕', 'dependencies' => {} }

    with_package_json(package.to_json) do
      get '@rubygems/gem1'

      assert_equal 200, response.status
      assert_equal package, packed_package_json(fetch_tarball)
    end
  end
end
