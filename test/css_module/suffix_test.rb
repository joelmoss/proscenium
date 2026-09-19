# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

# A CSS module class name is `<name>_<digest>_<suffix>`. The class names a view emits are built by
# Ruby, and the class names the stylesheet defines are built by Go (esbuild-internal's
# `CssLocalAppendice`). The suffix has to agree byte for byte, or the style silently does not apply.
class Proscenium::CssModule::SuffixTest < ActiveSupport::TestCase
  # The expected values are the output of Go's `CssLocalAppendice`, not of the Ruby implementation.
  GO_SUFFIXES = {
    'lib/styles.module.css' => 'lib-styles-module',
    'app/components/button/component.module.css' => 'app-components-button-component-module',
    'node_modules/@scope/pkg/x.module.css' => 'node_modules-_scope-pkg-x-module',
    'lib/a+b/x.module.css' => 'lib-a_b-x-module',
    'lib/sp ace/x~y.module.css' => 'lib-sp_ace-x_y-module',
    '../../gems/foo-1.2.3/app/x.module.css' => '------gems-foo-1-2-3-app-x-module',
    '2024/x.module.css' => '_2024-x-module',
    'lib/Café/x.module.css' => 'lib-Caf_-x-module',
    'lib/back\\slash/x.module.css' => 'lib-back-slash-x-module',
    'lib/dots.in.dir/x.module.css' => 'lib-dots-in-dir-x-module',
    'lib/under_score-dash/x.module.css' => 'lib-under_score-dash-x-module',
    'lib/emoji😀/x.module.css' => 'lib-emoji_-x-module',
    'lib/a$b#c%d(e)/x.module.css' => 'lib-a_b_c_d_e_-x-module',
    'x.module.css' => 'x-module',
    'lib/no_ext' => 'lib-no_ext'
  }.freeze

  describe 'Utils.css_module_suffix' do
    GO_SUFFIXES.each do |path, expected|
      it "matches Go for #{path.inspect}" do
        assert_equal expected, Proscenium::Utils.css_module_suffix(path)
      end
    end
  end

  describe 'a class name emitted for a CSS module that Go builds' do
    before { @tmp = Pathname.new(Dir.mktmpdir('css_names', Rails.root.join('tmp').to_s)) }
    after { FileUtils.rm_rf(@tmp) }

    {
      'a plain path' => 'plain',
      'an @ and a +' => '@scope/pk+g',
      'a space and a ~' => 'sp ace~x'
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
        in_js = build.call("#{rel}/x.js")[/myClass_[A-Za-z0-9_-]+/]

        assert_equal emitted, in_stylesheet
        assert_equal emitted, in_js
      end
    end
  end
end
