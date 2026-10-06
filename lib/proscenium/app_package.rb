# frozen_string_literal: true

require 'json'

module Proscenium
  # What the app's own package.json says that the context map needs (#154). Like ContextMap, which
  # it reads JSON through, it loads nothing the `proscenium` CLI may not.
  module AppPackage
    LOCAL_SPECS = %w[link: file: workspace: portal:].freeze

    module_function

    # The names of the app's own `link:`, `file:` and workspace dependencies, peers included, as
    # pnpm installs those too, and in a Bun app any workspace member it depends on by version,
    # which Bun links. They keep their link paths once dependency contexts make other packages
    # real-path.
    def local_packages(root)
      package = read(root) or return []

      members = bun?(root, package) ? workspace_members(root, package['workspaces']) : []
      %w[dependencies devDependencies optionalDependencies peerDependencies].flat_map do |field|
        deps = package[field]
        next [] unless deps.is_a?(Hash)

        deps.select { |name, spec| spec.to_s.start_with?(*LOCAL_SPECS) || members.include?(name) }
            .keys
      end.uniq.sort
    end

    # Whether Bun installs the app: packageManager names it, or else its lockfile is there.
    def bun?(root, package)
      named = package['packageManager']
      return named.split('@').first == 'bun' if named.is_a?(String)

      %w[bun.lock bun.lockb].any? { File.exist?(File.join(root, it)) }
    end

    # The names of the packages `workspaces` (an array, or an object's `packages`) takes in, less
    # those a `!` pattern leaves out, read as Bun's glob does: braces and `**` included.
    def workspace_members(root, workspaces)
      patterns = Array(workspaces.is_a?(Hash) ? workspaces['packages'] : workspaces).grep(String)
      excluded, included = patterns.map { it.delete_prefix('./').chomp('/') }
                                   .partition { it.start_with?('!') }
      dirs = included.flat_map { Dir.glob(it, File::FNM_EXTGLOB, base: root) }.uniq
      dirs.reject { |dir| excluded.any? { File.fnmatch?(it[1..], dir, File::FNM_EXTGLOB) } }
          .filter_map { read(File.join(root, it))&.dig('name') }
    end

    # Whether package.json's text, for a file JSON.parse refuses, registers the contexts in its
    # `workspaces`, decoding JSON's `\/` and `\uXXXX`
    # escapes in the key and the pattern, as Bun does.
    def workspaces?(text) = unescape(text).match?(WORKSPACES)

    # JSON text with its `\uXXXX` and `\/` escapes decoded, as Bun reads them, for matching a file
    # JSON.parse refuses.
    # A surrogate pair is one character; a lone half, which JSON allows, becomes U+FFFD rather
    # than raising.
    def unescape(text)
      text.gsub(ESCAPE) do
        high, low, single = ::Regexp.last_match.captures
        if high then (0x10000 + ((high.hex - 0xD800) << 10) + (low.hex - 0xDC00)).chr(Encoding::UTF_8)
        elsif single then SURROGATES.cover?(single.hex) ? "\uFFFD" : single.hex.chr(Encoding::UTF_8)
        else '/'
        end
      end
    end

    ESCAPE = %r{\\u([dD][89abAB]\h{2})\\u([dD][c-fC-F]\h{2})|\\u(\h{4})|\\/}
    SURROGATES = (0xD800..0xDFFF)

    # The pattern inside package.json's `workspaces`, an array or an object's `packages`.
    WORKSPACES = /"workspaces"\s*:\s*(?:\{[^}]*"packages"\s*:\s*)?\[[^\]]*
                  "\.proscenium\/packages\/\*"/x

    # The manager `packageManager` names, or nil.
    def package_manager(root)
      field = read(root)&.dig('packageManager')
      field.split('@').first if field.is_a?(String)
    end

    # The app's package.json as an object, or nil when it is missing or not one.
    def read(root)
      path = File.join(root, 'package.json')
      package = File.exist?(path) && ContextMap.read_json(path)
      package if package.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
  end
end
