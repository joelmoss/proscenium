# frozen_string_literal: true

require 'test_helper'

class Proscenium::BuilderTest < Minitest::Test
  def test_build_multiple_files # rubocop:disable Minitest/MultipleAssertions
    result = Proscenium::Builder.build('lib/code_splitting/son.js;lib/code_splitting/daughter.js')

    assert_includes result, 'assets/lib/code_splitting/son$PBRCBJYT$.js.map;'
    assert_includes result, 'assets/lib/code_splitting/son$PBRCBJYT$.js;'
    assert_includes result, 'assets/lib/code_splitting/daughter$MTOCBJXF$.js.map;'
    assert_includes result, 'assets/lib/code_splitting/daughter$MTOCBJXF$.js;'
    assert_includes result, 'assets/_chunks/chunk-3NURZD3X.js.map;'
    assert_includes result, 'assets/_chunks/chunk-3NURZD3X.js'
  end

  def test_build_basic_js
    result = Proscenium::Builder.build('lib/foo.js')

    assert_includes result, 'console.log("/lib/foo.js");'
    assert_includes result, '//# sourceMappingURL=foo.js.map'
  end

  def test_build_basic_css
    result = Proscenium::Builder.build('lib/foo.css')

    assert_includes result, ".body {\n  color: red;\n}"
    assert_includes result, '/*# sourceMappingURL=foo.css.map */'
  end

  def test_build_source_map_js
    result = Proscenium::Builder.build('lib/foo.js.map')

    assert_includes result, "\"sourcesContent\": [\"console.log('/lib/foo.js')\\n\""
  end

  def test_build_source_map_css
    result = Proscenium::Builder.build('lib/foo.css.map')

    assert_includes result, '"sourcesContent": [".body {\\ncolor: red;\\n}\\n"'
  end

  def test_resolve
    result = Proscenium::Builder.resolve('is-ip')

    assert_equal '/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js', result
  end

  def test_build_unknown_path
    error = assert_raises Proscenium::Builder::BuildError do
      Proscenium::Builder.new.build('unknown.js')
    end

    assert_equal "Failed to build 'unknown.js' -- Could not resolve \"unknown.js\"", error.message
  end
end
