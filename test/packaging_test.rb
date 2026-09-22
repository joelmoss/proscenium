# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'open3'

# What a built gem contains, and what happens to someone whose platform has no gem.
#
# Both are packaging behaviour, which nothing else here covers: the rest of the suite starts from
# a library that has already loaded. The released 0.25.2 carries an x86-64 Linux ELF inside its
# platform-less gem because `rake build` compiles for each platform and then lets Bundler build
# the plain gem last, in the same working tree, so it packed whatever the final compile left in
# lib/proscenium/ext/. A user on a platform Proscenium does not build for installs that gem and
# gets a dlopen failure naming a path, with nothing to say their platform is simply unsupported.
class Proscenium::PackagingTest < ActiveSupport::TestCase
  ROOT = Pathname.new(__dir__).join('..').expand_path

  # Loaded in a subprocess per case: Gem::Specification.load memoises per path, so toggling the
  # environment variable in this process would read back the first answer either way.
  def gemspec_ext_files(package_ext:)
    script = 'print Gem::Specification.load("proscenium.gemspec")' \
             '.files.grep(%r{\Alib/proscenium/ext/}).join(",")'
    env = { 'PROSCENIUM_PACKAGE_EXT' => (package_ext ? '1' : nil) }
    out, err, status = Open3.capture3(env, RbConfig.ruby, '-e', script, chdir: ROOT.to_s)

    assert_predicate status, :success?, "gemspec failed to load: #{err}"

    out.split(',').reject(&:empty?)
  end

  describe 'the gemspec' do
    it 'omits the compiled library, so the platform-less gem carries no binary' do
      assert_empty gemspec_ext_files(package_ext: false)
    end

    it 'includes the compiled library when the platform build tasks ask for it' do
      # Guards the other direction: a gate that excluded the library unconditionally would pass
      # the test above and ship six platform gems with nothing in them.
      #
      # Named through LIBRARY_NAME, which is `proscenium.dll` on Windows: a hard-coded name found
      # nothing there, so this skipped on the one platform whose gem was still to be built.
      library = "lib/proscenium/ext/#{Proscenium::Builder::LIBRARY_NAME}"
      skip 'no compiled library present - run `rake compile:local`' unless ROOT.join(library).exist?

      assert_includes gemspec_ext_files(package_ext: true), library
    end
  end

  # The release workflow proves each built gem by loading its library from an installed copy with
  # no Rails and no app (bin/verify-installed-gem), so builder.rb has to load on its own. It used
  # to subclass Proscenium::Error, defined only in lib/proscenium.rb, and failed with a NameError.
  describe 'the builder' do
    it 'loads and calls into Go without the rest of the gem' do
      _, err, status = Open3.capture3(
        RbConfig.ruby, '-I', ROOT.join('lib').to_s,
        # Aborts if anything pulled Rails in, because then this would prove nothing.
        '-e', 'require "proscenium/builder"; Proscenium::Builder.reset_config!; ' \
              'abort "Rails was loaded" if defined?(Rails)',
        chdir: ROOT.to_s
      )

      assert_predicate status, :success?, "builder.rb did not load on its own: #{err}"
    end
  end

  describe 'a platform with no compiled library' do
    it 'names the platform instead of failing inside FFI' do
      Dir.mktmpdir do |dir|
        lib = File.join(dir, 'lib')
        FileUtils.mkdir_p lib
        FileUtils.cp_r ROOT.join('lib/proscenium.rb').to_s, lib
        FileUtils.cp_r ROOT.join('lib/proscenium').to_s, lib
        FileUtils.rm_rf File.join(lib, 'proscenium/ext')

        _, err, status = Open3.capture3(
          RbConfig.ruby, '-I', lib, '-r', 'pathname',
          '-e', 'require "proscenium"; require "proscenium/builder"',
          chdir: ROOT.to_s
        )

        refute_predicate status, :success?, 'expected the load to fail without a library'
        assert_match(/Proscenium::Builder::UnsupportedPlatform/, err)
        assert_match(/no compiled library for this platform/, err)
        assert_match(/#{Regexp.escape(Gem::Platform.local.to_s)}/, err)
        # The FFI message this replaces. Its reappearance means the guard stopped running.
        refute_match(/Could not open library/, err)
      end
    end
  end
end
