# frozen_string_literal: true

require 'test_helper'

class Proscenium::UtilsTest < ActiveSupport::TestCase
  # Public API: a UI gem built on proscenium-phlex accepts `:required!` in place of
  # `required: true` through this.
  describe '.merge_bang_attributes!' do
    it 'turns an allowed bang name into a true attribute, removing it from the names' do
      names = %i[required! plain]
      attributes = {}
      Proscenium::Utils.merge_bang_attributes!(names, attributes, %i[required disabled])

      assert_equal [:plain], names
      assert_equal({ required: true }, attributes)
    end

    it 'leaves a bang name that is not allowed where it is' do
      names = [:hidden!]
      attributes = {}
      Proscenium::Utils.merge_bang_attributes!(names, attributes, %i[required])

      assert_equal [:hidden!], names
      assert_empty attributes
    end

    it 'keeps an attribute given as a keyword over the bang' do
      names = [:required!]
      attributes = { required: false }
      Proscenium::Utils.merge_bang_attributes!(names, attributes, ['required'])

      assert_empty names
      assert_equal({ required: false }, attributes)
    end
  end
end
