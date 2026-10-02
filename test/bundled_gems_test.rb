# frozen_string_literal: true

require 'test_helper'

class Proscenium::BundledGemsTest < ActiveSupport::TestCase
  describe '.virtual_path' do
    def with_paths(paths)
      original = Proscenium::BundledGems.method(:paths)
      Proscenium::BundledGems.define_singleton_method(:paths) { paths }
      yield
    ensure
      Proscenium::BundledGems.define_singleton_method(:paths, original)
    end

    it 'maps a path inside a gem to its @rubygems form' do
      with_paths('gem1' => '/gems/gem1') do
        assert_equal '@rubygems/gem1/lib/x.js',
                     Proscenium::BundledGems.virtual_path('/gems/gem1/lib/x.js')
      end
    end

    it 'is nil for a path in no gem' do
      with_paths('gem1' => '/gems/gem1') do
        assert_nil Proscenium::BundledGems.virtual_path('/gems/gem1-other/x.js')
      end
    end

    # The longest root wins, as in Go's GemFromFsPath, so both sides credit a file under a nested
    # gem to the same gem. First-alphabetical gave `@rubygems/a-engine/vendor/z/x.js` here, a
    # second URL for a module Go loads as `@rubygems/z/x.js`.
    it 'credits a path under nested gem roots to the innermost gem' do
      with_paths('a-engine' => '/r', 'z' => '/r/vendor/z') do
        assert_equal '@rubygems/z/x.js', Proscenium::BundledGems.virtual_path('/r/vendor/z/x.js')
        assert_equal '@rubygems/a-engine/x.js', Proscenium::BundledGems.virtual_path('/r/x.js')
      end
    end

    # Two gems sharing one source tree: the first by name, which is Go's tie-break too.
    it 'breaks a tie between equal roots on gem name' do
      with_paths('a' => '/r', 'b' => '/r') do
        assert_equal '@rubygems/a/x.js', Proscenium::BundledGems.virtual_path('/r/x.js')
      end
    end

    # The gem path is text, not a pattern. Interpolated into a regex, `+` matched one or more of
    # the character before it, so this path was left unmapped, and an unbalanced `(` raised.
    it 'matches a gem path holding regex metacharacters literally' do
      with_paths('gem1' => '/gems/gem1-1.0+build', 'gem2' => '/gems/(gem2') do
        assert_equal '@rubygems/gem1/x.js',
                     Proscenium::BundledGems.virtual_path('/gems/gem1-1.0+build/x.js')
        assert_equal '@rubygems/gem2/x.js', Proscenium::BundledGems.virtual_path('/gems/(gem2/x.js')
      end
    end
  end
end
