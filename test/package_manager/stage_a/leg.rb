# frozen_string_literal: true

# A Stage A leg (#154): one gem's JavaScript dependencies through a hand-written context, on pnpm
# or Bun, compared with the app's install today. Local only: it reads the maintainer's checkouts
# of an app (london, codaset) and of the gem the app's bundle points at, and writes everything
# under OUT. It never writes to either checkout, and nothing from them is committed.
#
#   ruby test/package_manager/stage_a/leg.rb APP GEM_ROOT CONFIG OUT
#
# It needs the app's Ruby (via mise) to list its bundle, the app's package manager, and Go.
#
# CONFIG is a local JSON file holding the app's settings, kept out of the repository with the rest
# of the app's configuration:
#
#   { "gem": name, "manager": "pnpm" | "bun",
#     "entries": [the gem's entry points the app uses, as paths or globs relative to GEM_ROOT],
#     "aliases": { name: target }, "externals": [specifier],
#     "copy": [app paths an alias points at, copied with the JS configuration] }
#
# Each cell is a copy of the app's JS configuration. `base` installs it as it is, with the frozen
# lockfile. The others drop the app's dependency on `@rubygems/<gem>` (a `github:` pin or a
# registry package), register `.proscenium/packages/*`, write the gem's context and install; `ref`
# cells also depend on the context with `workspace:*`. On Bun, `reg` registers with no linker
# setting, to see what Bun picks, and the others set the linker and an empty
# `trustedDependencies`, as the plan requires. Every entry is then built in each cell, bundled and
# unbundled, with the Stage A seam on and off, and compared with `base`.

require 'fileutils'
require 'json'
require 'open3'
require_relative 'context'

app_dir, gem_root, config, out = ARGV.map { File.expand_path(it) }
abort 'usage: leg.rb APP GEM_ROOT CONFIG OUT' unless out
config = JSON.parse(File.read(config))
GEM = config.fetch('gem')
MANAGER = config.fetch('manager')

REPO = File.expand_path('../../..', __dir__)
MODES = { 'bundled' => [], 'unbundled' => ['-unbundle'] }.freeze

# name => [app edge to the context, Bun linker (nil: leave unset), whether to build it]
CELLS = if MANAGER == 'pnpm'
          { 'unref' => [false, nil, true], 'ref' => [true, nil, true] }
        else
          { 'reg' => [false, nil, false],
            'unref-hoisted' => [false, 'hoisted', true],
            'unref-isolated' => [false, 'isolated', true],
            'ref-hoisted' => [true, 'hoisted', true] }
        end.freeze
COPIED = { 'pnpm' => %w[package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc],
           'bun' => %w[package.json bun.lock bunfig.toml .npmrc] }.fetch(MANAGER).freeze

def run!(*cmd, chdir: Dir.pwd, env: {})
  output, status = Open3.capture2e(env, *cmd, chdir:)
  raise "#{cmd.join(' ')} failed:\n#{output}" unless status.success?

  output
end

# OUT is deleted and rebuilt on every run, so it must be this script's own directory: empty, or
# marked by an earlier run, and holding neither checkout nor this repository.
MARKER = '.stage_a_leg'
[app_dir, gem_root, REPO].each do |dir|
  abort "OUT (#{out}) would contain #{dir}" if dir == out || dir.start_with?("#{out}/")
end
if File.directory?(out) && !Dir.empty?(out) && !File.exist?("#{out}/#{MARKER}")
  abort "OUT (#{out}) is not empty and was not made by this script; refusing to delete it"
end
FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)
FileUtils.touch("#{out}/#{MARKER}")

# Bundled gems as the app's bundle sees them, read without touching its Gemfile.lock.
gems = run!('mise', 'exec', '--', 'ruby', '-rbundler', '-e', <<~RUBY, chdir: app_dir)
  Bundler.load.specs.reject { it.name == 'bundler' }.sort_by(&:name).each do |s|
    root = s.name == 'proscenium' ? File.join(s.full_gem_path, 'lib/proscenium') : s.full_gem_path
    puts [s.name, root].join("\t")
  end
RUBY
# Bundler may print progress ("Resolving dependencies...") before the list.
gems = gems.lines.grep(/\t/).join
File.write("#{out}/gems.tsv", gems)
unless gems.include?("#{GEM}\t#{gem_root}\n")
  abort "the app's bundle does not point #{GEM} at #{gem_root}"
end

entries = config.fetch('entries').flat_map { Dir.glob(it, base: gem_root).sort }.uniq
File.write("#{out}/entries.txt", entries.map { "node_modules/@rubygems/#{GEM}/#{it}\n" }.join)

# What a cell's install left behind: the linker's store, anything Bun moved aside on a linker
# switch, and where the context's dependencies are.
def layout(dir)
  modules = "#{dir}/node_modules"
  context = "#{dir}/.proscenium/packages/#{GEM}/node_modules"
  {
    'store' => %w[.pnpm .bun].select { File.directory?("#{modules}/#{it}") },
    'moved_aside' => Dir.glob('.old_modules-*', base: modules),
    'context_entries' => File.directory?(context) ? Dir.children(context).sort : nil,
    'root_entries' => Dir.exist?(modules) ? Dir.children(modules).count { !it.start_with?('.') } : 0
  }
end

# Adds the context pattern to the app's workspaces, keeping any it has, in either of the forms
# package.json allows (an array, or an object with `packages`).
def register_bun(app)
  pattern = '.proscenium/packages/*'
  workspaces = app['workspaces'] ||= []
  list = workspaces.is_a?(Hash) ? (workspaces['packages'] ||= []) : workspaces
  list << pattern unless list.include?(pattern)
end

# Sets `linker` in bunfig.toml's `[install]` table, adding the table only if there is none: a
# second `[install]` would make the file invalid TOML.
def set_linker(path, linker)
  lines = File.exist?(path) ? File.readlines(path) : []
  lines.reject! { it.match?(/\A\s*linker\s*=/) }
  table = lines.index { it.strip == '[install]' }
  if table
    lines.insert(table + 1, "linker = \"#{linker}\"\n")
  else
    lines << "\n" unless lines.empty?
    lines.push("[install]\n", "linker = \"#{linker}\"\n")
  end
  File.write(path, lines.join)
end

layouts = {}
(['base'] + CELLS.keys).each do |cell|
  dir = "#{out}/#{cell}"
  FileUtils.mkdir_p(dir)
  COPIED.each { FileUtils.cp("#{app_dir}/#{it}", dir) if File.exist?("#{app_dir}/#{it}") }
  config.fetch('copy', []).each do |path|
    FileUtils.mkdir_p(File.dirname("#{dir}/#{path}"))
    FileUtils.cp_r("#{app_dir}/#{path}", "#{dir}/#{path}")
  end

  unless cell == 'base'
    edge, linker, = CELLS.fetch(cell)
    app = JSON.parse(File.read("#{dir}/package.json"))
    app['dependencies'].delete("@rubygems/#{GEM}")
    app['dependencies']["@rubygems/#{GEM}"] = 'workspace:*' if edge
    if MANAGER == 'bun'
      register_bun(app)
      app['trustedDependencies'] ||= [] if linker
      set_linker("#{dir}/bunfig.toml", linker) if linker
    else
      StageA::Context.register_pnpm(dir)
    end
    File.write("#{dir}/package.json", "#{JSON.pretty_generate(app)}\n")
    StageA::Context.write(dir, GEM, gem_root)
  end

  args = cell == 'base' ? ['--frozen-lockfile'] : []
  log = run!(MANAGER, 'install', *args, chdir: dir)
  File.write("#{dir}/install.log", log)
  layouts[cell] = layout(dir)
  summary = log.lines.grep(/Done in|packages installed|Blocked|Ignored build scripts/).map(&:strip)
  puts "#{cell}: #{summary.join(' | ')}"
  puts "  layout: #{layouts[cell].except('context_entries').to_json}"
end
File.write("#{out}/layouts.json", JSON.pretty_generate(layouts))

probe = "#{out}/probe"
run!('go', 'build', '-o', probe, './test/package_manager/stage_a/probe', chdir: REPO,
                                                                         env: { 'GOWORK' => 'off' })

flags = config.fetch('externals', []).flat_map { ['-external', it] } +
        config.fetch('aliases', {}).flat_map { |key, target| ['-alias', "#{key}=#{target}"] }

runs = { 'base' => ['base', []] }
CELLS.each do |cell, (_, _, build)|
  next unless build

  context_dir = File.realpath("#{out}/#{cell}/.proscenium/packages/#{GEM}")
  runs["#{cell}+off"] = [cell, []]
  runs["#{cell}+seam"] = [cell, ['-context', "#{GEM}=#{context_dir}"]]
end

summaries = {}
runs.each do |name, (cell, extra)|
  MODES.each do |mode, mode_flags|
    dir = "#{out}/out/#{name}+#{mode}"
    run!(probe, '-root', "#{out}/#{cell}", '-gems', "#{out}/gems.tsv", '-entries',
         "#{out}/entries.txt", '-out', dir, *flags, *extra, *mode_flags)
    summaries["#{name}+#{mode}"] = File.readlines("#{dir}/summary.tsv", chomp: true).to_h do |line|
      entry, status, found = line.split("\t", 3)
      [entry, [status, found.to_s.split]]
    end
  end
end

# A module or import as package@version/subpath, so installs in different directories compare.
# A gem's own file keeps its URL. Unbundled URLs under /node_modules/@rubygems/<gem>/node_modules/
# are served from the gem root, so they resolve against it.
def identity(path, root, gem_root)
  return path if path.match?(%r{\A/?node_modules/@rubygems/[^/]+/(?!node_modules/)})

  gem_url = "/node_modules/@rubygems/#{GEM}/"
  fs = if path.start_with?(gem_url) then "#{gem_root}/#{path.delete_prefix(gem_url)}"
       elsif path.start_with?('/') then "#{root}#{path}"
       else File.expand_path(path, root)
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
base_root = File.realpath("#{out}/base")
summaries.each_key do |name|
  next if name.start_with?('base')

  cell = name.split('+').first
  mode = name.split('+').last
  base = summaries["base+#{mode}"]
  root = File.realpath("#{out}/#{cell}")
  differ = base.filter_map do |entry, (status, found)|
    new_status, new_found = summaries[name][entry]
    a = found.map { identity(it, base_root, gem_root) }.sort
    b = new_found.map { identity(it, root, gem_root) }.sort
    next if status == new_status && a == b

    "  #{entry.delete_prefix("node_modules/@rubygems/#{GEM}/")}: #{status} -> #{new_status}, " \
      "#{(a - b).size} only in base, #{(b - a).size} only here"
  end
  puts "#{name}: #{base.size - differ.size} of #{base.size} entries match base"
  puts differ
end
