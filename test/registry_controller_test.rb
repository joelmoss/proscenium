# frozen_string_literal: true

require 'test_helper'

class Proscenium::RegistryControllerTest < ActiveSupport::TestCase
  attr_reader :response

  let(:tarballs) { Rails.public_path.join('proscenium_registry_tarballs') }
  let(:gem1_version) { Bundler.load.specs['gem1'].first.version.to_s }

  # Tarballs are a cache the controller rebuilds whenever one is missing, so clearing the dummy
  # app's is safe. Before as well as after, as one left by `rails server` would fail the
  # assertions that nothing was written.
  before { FileUtils.rm_rf tarballs }
  after { FileUtils.rm_rf tarballs }

  # The engine is a Rack app in its own right, so it is called directly rather than mounted into
  # the dummy app.
  def get(path)
    @response = Rack::MockRequest.new(Proscenium::Railtie).get("/registry/#{path}")
  end

  def json = JSON.parse(response.body)

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

  def packed_package_json
    tarball = tarballs.join("@rubygems/gem1/gem1-#{gem1_version}.tgz")
    packed = Zlib::GzipReader.open(tarball) do |gz|
      Gem::Package::TarReader.new(gz).each do |entry|
        break entry.read if entry.full_name == 'package/package.json'
      end
    end
    JSON.parse(packed.force_encoding(Encoding::UTF_8))
  end

  it 'serves an installed gem at its installed version' do
    get '@rubygems/gem1'

    assert_equal 200, response.status
    assert_equal '@rubygems/gem1', json['name']
    assert_equal gem1_version, json.dig('dist-tags', 'latest')
    assert_equal %w[open-props string-length],
                 json.dig('versions', gem1_version, 'dependencies').keys.sort
    assert_path_exists tarballs.join("@rubygems/gem1/gem1-#{gem1_version}.tgz")
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

  it 'answers 404 for a version that is not the installed one, and writes nothing' do
    get '@rubygems/gem1/99.9.9'

    assert_equal 404, response.status
    assert_match(/99\.9\.9/, json['error'])
    refute_path_exists tarballs
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
      with_gem_path('gem1', dir) { get '@rubygems/gem1' }

      assert_equal 200, response.status
      assert_empty json.dig('versions', gem1_version, 'dependencies')
      assert_equal gem1_version, packed_package_json['version']
      assert_empty packed_package_json['dependencies']
    end
  end

  # A tar entry's size is in bytes. Sized in characters, a package.json with any non-ASCII text
  # overflows its entry.
  it 'packs a package.json with non-ASCII text' do
    Dir.mktmpdir do |dir|
      package = { 'name' => '@rubygems/gem1', 'description' => 'Café ☕', 'dependencies' => {} }
      File.write File.join(dir, 'package.json'), package.to_json

      with_gem_path('gem1', dir) { get '@rubygems/gem1' }

      assert_equal 200, response.status
      assert_equal package, packed_package_json
    end
  end
end
