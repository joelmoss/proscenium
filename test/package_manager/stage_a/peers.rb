# frozen_string_literal: true

# The Stage A peer probe (#154, C12): does a context share the app's copy of a peer when the app
# pins a non-latest version in the peer's range, and after the app bumps it?
#
#   PNPM="npx -y pnpm@10.33.1" BUN="npx -y bun@1.4.0" ruby test/package_manager/stage_a/peers.rb OUT
#
# PNPM and BUN default to `pnpm` and `bun`. The app pins react 18.2.0; one context declares
# `react: ^18.0.0` as a peer. For each manager setting below, with the context referenced from the
# app (`workspace:*`) and not, it installs, then bumps the app to 18.3.1 and installs again, and
# on pnpm then runs `pnpm dedupe`. Each time it records the React the app root and the context
# resolve (Node's require.resolve from each directory) and whether they are one real file. Needs
# Node and the network.

require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'

out = File.expand_path(ARGV.first || abort('usage: peers.rb OUT'))
MARKER = '.stage_a_peers'
if File.directory?(out) && !Dir.empty?(out) && !File.exist?("#{out}/#{MARKER}")
  abort "OUT (#{out}) is not empty and was not made by this script; refusing to delete it"
end
FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)
FileUtils.touch("#{out}/#{MARKER}")

COMMANDS = { 'pnpm' => Shellwords.split(ENV.fetch('PNPM', 'pnpm')),
             'bun' => Shellwords.split(ENV.fetch('BUN', 'bun')) }.freeze
VARIANTS = {
  'pnpm' => { 'pnpm-default' => '', 'pnpm-no-auto-install-peers' => "auto-install-peers=false\n",
              'pnpm-no-peers-from-root' => "resolve-peers-from-workspace-root=false\n" },
  'bun' => { 'bun-hoisted' => 'hoisted', 'bun-isolated' => 'isolated' }
}.freeze
EDGES = [true, false].freeze
CONTEXT = { 'name' => '@rubygems/widget', 'private' => true,
            'peerDependencies' => { 'react' => '^18.0.0' } }.freeze
COLUMNS = %w[setting edge step app context shared].freeze
ROW = '%-28s %-6s %-14s %-8s %-8s %s'

def run!(*cmd, chdir:)
  output, status = Open3.capture2e(*cmd, chdir:)
  raise "#{cmd.join(' ')} failed in #{chdir}:\n#{output}" unless status.success?

  output
end

# The react a directory resolves: its version and real path, or nils.
def react_from(dir)
  script = 'try { const p = require.resolve("react/package.json"); ' \
           'console.log(require(p).version + " " + require("fs").realpathSync(p)) } ' \
           'catch (e) { console.log("unresolved") }'
  version, path = run!('node', '-e', script, chdir: dir).strip.split(' ', 2)
  [version, path]
end

def setup(dir, manager, setting, edge)
  context = File.join(dir, '.proscenium/packages/widget')
  FileUtils.mkdir_p(context)
  File.write(File.join(context, 'package.json'), JSON.pretty_generate(CONTEXT))

  app = { 'name' => 'app', 'private' => true, 'dependencies' => { 'react' => '18.2.0' } }
  app['dependencies']['@rubygems/widget'] = 'workspace:*' if edge
  if manager == 'pnpm'
    File.write(File.join(dir, 'pnpm-workspace.yaml'), "packages:\n  - .proscenium/packages/*\n")
    File.write(File.join(dir, '.npmrc'), setting)
  else
    app['workspaces'] = ['.proscenium/packages/*']
    app['trustedDependencies'] = []
    File.write(File.join(dir, 'bunfig.toml'), "[install]\nlinker = \"#{setting}\"\n")
  end
  [app, context]
end

results = []
VARIANTS.each do |manager, variants|
  command = COMMANDS.fetch(manager)
  variants.each do |name, setting|
    EDGES.each do |edge|
      dir = File.join(out, "#{name}-#{edge ? 'ref' : 'unref'}")
      app, context = setup(dir, manager, setting, edge)

      steps = { 'pin 18.2.0' => -> { app['dependencies']['react'] = '18.2.0' },
                'bump 18.3.1' => -> { app['dependencies']['react'] = '18.3.1' } }
      steps['dedupe'] = -> {} if manager == 'pnpm'
      steps.each do |step, change|
        change.call
        File.write(File.join(dir, 'package.json'), JSON.pretty_generate(app))
        run!(*command, step == 'dedupe' ? 'dedupe' : 'install', chdir: dir)
        root_version, root_path = react_from(dir)
        context_version, context_path = react_from(context)
        results << [name, edge.to_s, step, root_version, context_version,
                    (!root_path.nil? && root_path == context_path).to_s]
      end
    end
  end
end

versions = COMMANDS.transform_values { run!(*it, '--version', chdir: out).strip }
File.write(File.join(out, 'results.json'),
           JSON.pretty_generate('versions' => versions, 'rows' => results))
puts "pnpm #{versions['pnpm']}, bun #{versions['bun']}"
puts format(ROW, *COLUMNS)
results.each { puts format(ROW, *it) }
