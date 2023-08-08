# frozen_string_literal: true

module Sus
  class Include
    def initialize(to_include)
      @to_include = to_include
    end

    def print(output)
      output.write('include ', :include, :variable, @to_include, :reset)
    end

    def call(assertions, subject)
      assertions.nested(self) do |x|
        x.assert(subject.include?(@to_include))
      end
    end
  end

  class Base
    def include(...)
      Include.new(...)
    end
  end
end
