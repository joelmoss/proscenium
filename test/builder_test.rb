# frozen_string_literal: true

require 'test_helper'

class Proscenium::BuilderTest < ActiveSupport::TestCase
  setup do
    Proscenium.config.env_vars = Set.new
    Proscenium.config.code_splitting = false
  end

  test 'build multiple files with code splitting' do # rubocop:disable Minitest/MultipleAssertions
    Proscenium.config.code_splitting = true
    result = Proscenium::Builder.build('lib/code_splitting/son.js;lib/code_splitting/daughter.js')

    assert_includes result, 'assets/lib/code_splitting/son$LAGMAD6O$.js.map;'
    assert_includes result, 'assets/lib/code_splitting/son$LAGMAD6O$.js;'
    assert_includes result, 'assets/lib/code_splitting/daughter$7JJ2HGHC$.js.map;'
    assert_includes result, 'assets/lib/code_splitting/daughter$7JJ2HGHC$.js;'
    assert_includes result, 'assets/_asset_chunks/chunk-646VT4MD.js.map;'
    assert_includes result, 'assets/_asset_chunks/chunk-646VT4MD.js'
  end

  test 'build basic js' do
    result = Proscenium::Builder.build('lib/foo.js')

    assert_includes result, 'console.log("/lib/foo.js");'
    assert_includes result, '//# sourceMappingURL=foo.js.map'
  end

  test 'build basic css' do
    result = Proscenium::Builder.build('lib/foo.css')

    assert_includes result, ".body {\n  color: red;\n}"
    assert_includes result, '/*# sourceMappingURL=foo.css.map */'
  end

  test 'build source map js' do
    result = Proscenium::Builder.build('lib/foo.js.map')

    assert_includes result, "\"sourcesContent\": [\"console.log('/lib/foo.js')\\n\""
  end

  test 'build source map css' do
    result = Proscenium::Builder.build('lib/foo.css.map')

    assert_includes result, '"sourcesContent": [".body {\\ncolor: red;\\n}\\n"'
  end

  test 'env vars' do
    result = Proscenium::Builder.build('lib/env/env.js')

    assert_includes result, 'console.log("testtest")'
  end

  test 'extra env vars' do
    Proscenium.config.env_vars << 'USER_NAME'
    ENV['USER_NAME'] = 'joelmoss'
    result = Proscenium::Builder.build('lib/env/extra.js')

    assert_includes result, 'console.log("joelmoss")'
  end

  test 'resolve' do
    result = Proscenium::Builder.resolve('is-ip')

    assert_equal '/node_modules/.pnpm/is-ip@5.0.0/node_modules/is-ip/index.js', result
  end

  test 'build unknown path' do
    error = assert_raises Proscenium::Builder::BuildError do
      Proscenium::Builder.new.build('unknown.js')
    end

    assert_equal "Failed to build 'unknown.js' -- Could not resolve \"unknown.js\"", error.message
  end
end
