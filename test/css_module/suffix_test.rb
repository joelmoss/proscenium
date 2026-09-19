# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'tmpdir'

# A CSS module class name is `<name>_<digest>_<suffix>`. The class names a view emits are built by
# Ruby, and the class names the stylesheet defines are built by Go (esbuild-internal's
# `CssLocalAppendice`). The suffix has to agree byte for byte, or the style silently does not apply.
class Proscenium::CssModule::SuffixTest < ActiveSupport::TestCase
  # The expected values are the output of Go's `CssLocalAppendice`, not of the Ruby implementation,
  # and test/css_module_suffix_test.go checks the same rows against Go, so a change on either side
  # fails a test on that side. A row has a `path`, or a `hex` for a path that is not valid UTF-8 and
  # so cannot be written in JSON.
  GO_SUFFIXES = JSON.parse(File.read(File.expand_path('../css_module_suffixes.json', __dir__)))
                    .map { |row| [row['path'] || [row['hex']].pack('H*'), row['suffix']] }
                    .freeze

  describe 'Utils.css_module_suffix' do
    GO_SUFFIXES.each do |path, expected|
      # Paths that Go hands back over FFI are tagged ASCII-8BIT, and Go works in runes, not bytes.
      tagged_as = { 'UTF-8' => path.dup.force_encoding(Encoding::UTF_8), 'binary' => path.b }
      tagged_as.each do |tag, tagged|
        it "matches Go for #{path.inspect} tagged #{tag}" do
          assert_equal expected, Proscenium::Utils.css_module_suffix(tagged)
        end
      end
    end
  end

  describe 'a class name emitted for a CSS module that Go builds' do
    before { @tmp = Pathname.new(Dir.mktmpdir('css_names', Rails.root.join('tmp').to_s)) }
    after { FileUtils.rm_rf(@tmp) if @tmp }

    {
      'a plain path' => 'plain',
      'an @ and a +' => '@scope/pk+g',
      'a space and a ~' => 'sp ace~x',
      'a non-ASCII directory' => 'café'
    }.each do |label, subdir|
      it "is the class the stylesheet and the JS module define, for #{label}" do
        dir = @tmp.join(subdir)
        FileUtils.mkdir_p(dir)
        File.write(dir.join('x.module.css'), ".myClass {\n  color: red;\n}\n")
        File.write(dir.join('x.js'), "import s from './x.module.css'\nconsole.log(s.myClass)\n")

        rel = dir.relative_path_from(Rails.root).to_s
        build = ->(file) { Proscenium::Builder.new(root: Rails.root, Write: false).build_to_string(file)[:response] }

        emitted = Proscenium::CssModule::Transformer.class_names("/#{rel}/x", :@myClass).first
        in_stylesheet = build.call("#{rel}/x.module.css")[/\.(myClass_[^\s{:,]+)/, 1]

        # The JS module inlines the stylesheet, so the first `myClass_` in it is the stylesheet's
        # class, not the name the exported Proxy returns. The Proxy builds its names separately
        # (internal/plugin/css.go), as `p + "_<digest>_<suffix>"`, so read the suffix from there.
        proxy_suffix = build.call("#{rel}/x.js")[/\bp \+ ["'](_[^"']+)["']/, 1]

        assert_equal emitted, in_stylesheet
        refute_nil proxy_suffix, 'no class-name Proxy found in the JS module'
        assert_equal emitted, "myClass#{proxy_suffix}"
      end
    end
  end
end
