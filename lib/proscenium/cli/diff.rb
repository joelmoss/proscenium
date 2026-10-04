# frozen_string_literal: true

module Proscenium
  module CLI
    # A unified diff of a small text file's edit, which `install` prints before it writes one of
    # the app's files. Line-based, over a longest common subsequence: fine for the files it is
    # used on, which are a few dozen lines.
    module Diff
      MARKS = { same: ' ', del: '-', add: '+' }.freeze

      module_function

      # The diff of `before` to `after`, headed with `path`; empty when they are the same.
      def unified(path, before, after, context: 3)
        ops = lcs_ops(before.lines(chomp: true), after.lines(chomp: true))
        hunks = hunks(ops, context)
        return '' if hunks.empty?

        header = "--- #{path}\n+++ #{path}\n"
        header + hunks.map { |hunk| format_hunk(hunk) }.join
      end

      # Each line as [:same | :del | :add, text, line in old, line in new].
      def lcs_ops(old, new)
        table = lcs_table(old, new)
        ops = []
        i = j = 0
        while i < old.size || j < new.size
          if i < old.size && j < new.size && old[i] == new[j]
            ops << [:same, old[i], i, j]
            i += 1
            j += 1
          elsif j < new.size && (i == old.size || table[i][j + 1] >= table[i + 1][j])
            ops << [:add, new[j], i, j]
            j += 1
          else
            ops << [:del, old[i], i, j]
            i += 1
          end
        end
        ops
      end

      # The longest common subsequence lengths of every pair of suffixes.
      def lcs_table(old, new)
        table = Array.new(old.size + 1) { Array.new(new.size + 1, 0) }
        (old.size - 1).downto(0) do |i|
          (new.size - 1).downto(0) do |j|
            table[i][j] = if old[i] == new[j]
                            table[i + 1][j + 1] + 1
                          else
                            [table[i + 1][j], table[i][j + 1]].max
                          end
          end
        end
        table
      end

      def hunks(ops, context)
        changed = ops.each_index.reject { ops[it][0] == :same }
        return [] if changed.empty?

        groups = changed.slice_when { |x, y| y - x > context * 2 }
        groups.map do |group|
          ops[[group.first - context, 0].max..[group.last + context, ops.size - 1].min]
        end
      end

      def format_hunk(ops)
        a_start = ops.first[2] + 1
        b_start = ops.first[3] + 1
        a_count = ops.count { it[0] != :add }
        b_count = ops.count { it[0] != :del }
        lines = ops.map { |op, text| "#{MARKS.fetch(op)}#{text}\n" }
        "@@ -#{a_count.zero? ? a_start - 1 : a_start},#{a_count} " \
          "+#{b_count.zero? ? b_start - 1 : b_start},#{b_count} @@\n#{lines.join}"
      end
    end
  end
end
