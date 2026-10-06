# frozen_string_literal: true

module Proscenium
  module CLI
    # The `.gitignore` lines for Proscenium's own state (#154): everything under .proscenium/
    # ignored but the generated contexts, which are committed.
    module Gitignore
      # Each level down to a context's package.json is re-included: Git never looks inside a
      # directory an earlier rule (`.proscenium/`, `.*`) ignores, and `.proscenium/**` ignores
      # every level below it.
      IGNORES = ['!.proscenium/', '.proscenium/*', '!.proscenium/packages/',
                 '!.proscenium/packages/*/', '!.proscenium/packages/*/package.json',
                 '.proscenium/packages/*/node_modules/'].freeze

      module_function

      # Appends the lines Proscenium owns, and a node_modules rule if the app has none (Bun moves
      # an old tree to node_modules/.old_modules-<hash> when its linker changes).
      def splice(text)
        lines = text.lines(chomp: true)
        # Only the lines together, in order, and with no rule after them that could hide the
        # contexts are enough; otherwise all of them again. Git applies the last matching rule.
        size = IGNORES.size
        at = (0..(lines.size - size)).reverse_each.find { lines[it, size] == IGNORES }
        hidden = at.nil? || lines[(at + size)..].any? { hides_contexts?(it) }
        wanted = hidden ? IGNORES.dup : []
        wanted.unshift('node_modules/') unless lines.any? { it.match?(%r{\A/?node_modules/?\z}) }
        return text if wanted.empty?

        nl = text.include?("\r\n") ? "\r\n" : "\n"
        separator = text.empty? || text.end_with?("\n") ? '' : nl
        "#{text}#{separator}#{nl unless text.empty?}# Proscenium#{nl}#{wanted.join(nl)}#{nl}"
      end

      FLAGS = [File::FNM_DOTMATCH, File::FNM_DOTMATCH | File::FNM_PATHNAME].freeze
      COMMITTED = %w[.proscenium .proscenium/packages].freeze

      # Whether an ignore rule could match a path the contexts are committed under. Generous: `*`
      # crosses `/` here, so at worst the lines are added once more than needed.
      def hides_contexts?(line)
        pattern = line.strip.delete_prefix('/').chomp('/')
        return false if pattern.empty? || pattern.start_with?('#', '!')

        # Git's `**/` also matches no directory at all. Ruby's does too with FNM_PATHNAME, inside a
        # pattern, but not at its start, so that prefix is also dropped; without FNM_PATHNAME, a
        # trailing `**` (and `*`) crosses `/` as Git's trailing `/**` does.
        # Any segment of the rule may name a gem's directory, such as `.proscenium/packages/hue/**`,
        # and one with a wildcard, class or brace, such as `[ah]ue`, may match any of them.
        names = ['gem', *pattern.split('/')]
        wide = pattern.split('/').map { it.match?(/[*?\[{]/) ? '*' : it }.join('/')
        paths = COMMITTED + names.flat_map do |name|
          ["#{COMMITTED.last}/#{name}", "#{COMMITTED.last}/#{name}/package.json"]
        end
        [pattern, wide].flat_map { [it, it.delete_prefix('**/')] }.uniq.any? do |glob|
          paths.any? do |path|
            FLAGS.any? { File.fnmatch?(glob, path, it) } ||
              File.fnmatch?(glob, File.basename(path), File::FNM_DOTMATCH)
          end
        end
      end
    end
  end
end
