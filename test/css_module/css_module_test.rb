# frozen_string_literal: true

require 'test_helper'

class Proscenium::CssModuleTest < ActiveSupport::TestCase
  let(:klass) { Class.new { include Proscenium::CssModule } }
  let(:path) { '/lib/css_modules/basic' }

  describe '.css_module' do
    it 'accepts an Array of names, ignoring nil, false and blank names' do
      assert_equal klass.css_module(:@title, :plain, path:),
                   klass.css_module([:@title, nil, false, '', ' ', :plain], path:)
    end
  end

  describe '.class_names' do
    it 'ignores nil, false and blank names' do
      assert_equal klass.class_names(:@title, :plain, path:),
                   klass.class_names([:@title, nil, false, '', ' ', :plain], path:)
    end

    it 'returns nil when given no names' do
      assert_nil klass.class_names(nil, false, '', path:)
    end
  end

  describe '#class_names' do
    it 'ignores nil, false and blank names' do
      assert_equal klass.new.class_names(:@title, :plain, path:),
                   klass.new.class_names([:@title, nil, false, '', ' ', :plain], path:)
    end

    it 'returns nil when given no names' do
      assert_nil klass.new.class_names(nil, false, '', path:)
    end
  end
end
