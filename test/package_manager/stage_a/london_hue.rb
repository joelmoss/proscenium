# frozen_string_literal: true

# The Stage A london leg (#154): hue's dependencies through a hand-written pnpm context, compared
# with london's install today. Local only: london and hue are private, so this reads the
# maintainer's checkouts and writes everything under OUT. Nothing from either is committed.
#
#   ruby test/package_manager/stage_a/london_hue.rb LONDON HUE CONFIG OUT
#
# LONDON is the london checkout and HUE the hue checkout london's bundle points at
# (BUNDLE_LOCAL__HUE). It never writes to either. It needs london's Ruby (via mise) to list the
# bundle, pnpm, and Go.
#
# CONFIG is a local JSON file holding what london's Proscenium initializer sets, kept out of the
# repository with the rest of london's configuration:
#
#   { "entries": [hue entry points london precompiles, as paths or globs relative to HUE],
#     "aliases": { name: target }, "externals": [specifier],
#     "copy": [app paths an alias points at, copied with the JS configuration] }
#
# Three copies of london's JS configuration are installed: `base` as it is today (hue from its
# `github:` pin), and `unref` and `ref` with the pin removed, `.proscenium/packages/*` registered
# and a context for hue, `ref` also depending on it with `workspace:*`. Every hue entry point
# london precompiles is then built in each, bundled and unbundled, with the Stage A seam on and
# off, and compared with `base`.

require 'fileutils'
require 'json'
require 'open3'
require_relative 'context'

london, hue, config, out = ARGV.map { File.expand_path(it) }
abort 'usage: london_hue.rb LONDON HUE CONFIG OUT' unless out
config = JSON.parse(File.read(config))

REPO = File.expand_path('../../..', __dir__)
CELLS = %w[base unref ref].freeze
COPIED = %w[package.json pnpm-lock.yaml .npmrc].freeze
MODES = { 'bundled' => [], 'unbundled' => ['-unbundle'] }.freeze

def run!(*cmd, chdir: Dir.pwd, env: {})
  output, status = Open3.capture2e(env, *cmd, chdir:)
  raise "#{cmd.join(' ')} failed:\n#{output}" unless status.success?

  output
end

FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)

# Bundled gems as london's bundle sees them, read without touching its Gemfile.lock.
gems = run!('mise', 'exec', '--', 'ruby', '-rbundler', '-e', <<~RUBY, chdir: london)
  Bundler.load.specs.reject { it.name == 'bundler' }.sort_by(&:name).each do |s|
    root = s.name == 'proscenium' ? File.join(s.full_gem_path, 'lib/proscenium') : s.full_gem_path
    puts [s.name, root].join("\t")
  end
RUBY
File.write("#{out}/gems.tsv", gems)
abort "london's bundle does not point hue at #{hue}" unless gems.include?("hue\t#{hue}\n")

entries = config.fetch('entries').flat_map { Dir.glob(it, base: hue).sort }.uniq
File.write("#{out}/entries.txt", entries.map { "node_modules/@rubygems/hue/#{it}\n" }.join)

CELLS.each do |cell|
  dir = "#{out}/#{cell}"
  FileUtils.mkdir_p(dir)
  COPIED.each { FileUtils.cp("#{london}/#{it}", dir) }
  config.fetch('copy', []).each do |path|
    FileUtils.mkdir_p(File.dirname("#{dir}/#{path}"))
    FileUtils.cp_r("#{london}/#{path}", "#{dir}/#{path}")
  end

  unless cell == 'base'
    app = JSON.parse(File.read("#{dir}/package.json"))
    app['dependencies'].delete('@rubygems/hue')
    app['dependencies']['@rubygems/hue'] = 'workspace:*' if cell == 'ref'
    File.write("#{dir}/package.json", "#{JSON.pretty_generate(app)}\n")
    StageA::Context.register_pnpm(dir)
    StageA::Context.write(dir, 'hue', hue)
  end

  args = cell == 'base' ? ['--frozen-lockfile'] : []
  puts "#{cell}: #{run!('pnpm', 'install', *args, chdir: dir).lines.grep(/Done in/).first}"
end

probe = "#{out}/probe"
run!('go', 'build', '-o', probe, './test/package_manager/stage_a/probe', chdir: REPO,
                                                                         env: { 'GOWORK' => 'off' })

flags = config.fetch('externals', []).flat_map { ['-external', it] } +
        config.fetch('aliases', {}).flat_map { |key, target| ['-alias', "#{key}=#{target}"] }

runs = { 'base' => ['base', []] }
%w[unref ref].each do |cell|
  context_dir = File.realpath("#{out}/#{cell}/.proscenium/packages/hue")
  runs["#{cell}-off"] = [cell, []]
  runs["#{cell}-seam"] = [cell, ['-context', "hue=#{context_dir}"]]
end

summaries = {}
runs.each do |name, (cell, extra)|
  MODES.each do |mode, mode_flags|
    dir = "#{out}/out/#{name}-#{mode}"
    run!(probe, '-root', "#{out}/#{cell}", '-gems', "#{out}/gems.tsv", '-entries',
         "#{out}/entries.txt", '-out', dir, *flags, *extra, *mode_flags)
    summaries["#{name}-#{mode}"] = File.readlines("#{dir}/summary.tsv", chomp: true).to_h do |line|
      entry, status, found = line.split("\t", 3)
      [entry, [status, found.to_s.split]]
    end
  end
end

# A module or import as package@version/subpath, so installs in different directories compare.
# A gem's own file keeps its URL. Unbundled URLs under /node_modules/@rubygems/hue/node_modules/
# are served from the gem root, so they resolve against hue.
def identity(path, root, hue)
  return path if path.match?(%r{\A/?node_modules/@rubygems/[^/]+/(?!node_modules/)})

  fs = if path.start_with?('/node_modules/@rubygems/hue/')
         "#{hue}/#{path.delete_prefix('/node_modules/@rubygems/hue/')}"
       elsif path.start_with?('/')
         "#{root}#{path}"
       else
         File.expand_path(path, root)
       end
  return path unless File.exist?(fs)

  real = File.realpath(fs)
  dir = File.dirname(real)
  until dir == '/'
    pkg = "#{dir}/package.json"
    if File.exist?(pkg)
      meta = JSON.parse(File.read(pkg))
      return "#{meta['name']}@#{meta['version']}#{real.delete_prefix(dir)}" if meta['version']
    end
    dir = File.dirname(dir)
  end
  real.delete_prefix(root)
end

puts
summaries.each_key do |name|
  next if name.start_with?('base')

  mode = name.split('-').last
  base = summaries["base-#{mode}"]
  root = File.realpath("#{out}/#{name.split('-').first}")
  base_root = File.realpath("#{out}/base")
  differ = base.filter_map do |entry, (status, found)|
    new_status, new_found = summaries[name][entry]
    a = found.map { identity(it, base_root, hue) }.sort
    b = new_found.map { identity(it, root, hue) }.sort
    next if status == new_status && a == b

    "  #{entry.delete_prefix('node_modules/@rubygems/hue/')}: #{status} -> #{new_status}, " \
      "#{(a - b).size} only in base, #{(b - a).size} only here"
  end
  puts "#{name}: #{base.size - differ.size} of #{base.size} entries match base"
  puts differ
end
