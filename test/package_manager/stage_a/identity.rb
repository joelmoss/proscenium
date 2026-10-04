# frozen_string_literal: true

# The Stage A browser identity probe (#154): with the seam on and pnpm's isolated layout, an app
# and a gem reach a shared peer through different links to one file. Unbundled, do they load it
# as one module in a real browser, or as two?
#
#   PLAYWRIGHT=/path/to/node_modules/playwright ruby test/package_manager/stage_a/identity.rb OUT
#
# It writes a small gem that takes preact as a peer, gives it a context in an app that declares
# preact, runs pnpm, and builds the page's modules unbundled through Proscenium::Builder,
# following every import the way the middleware would serve it, into a static directory. Node
# serves that directory and Playwright's Chromium loads the page, which reports whether the app's
# preact and the gem's are the same module. Needs pnpm, Node, Playwright and the network.

ENV['RAILS_ENV'] = 'test'
require_relative '../../../fixtures/dummy/config/environment'
require 'json'
require 'open3'
require_relative 'context'

out = File.expand_path(ARGV.first || abort('usage: identity.rb OUT'))
playwright = ENV.fetch('PLAYWRIGHT') do
  abort 'set PLAYWRIGHT to a node_modules/playwright directory'
end
MARKER = '.stage_a_identity'
if File.directory?(out) && !Dir.empty?(out) && !File.exist?("#{out}/#{MARKER}")
  abort "OUT (#{out}) is not empty and was not made by this script; refusing to delete it"
end
FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)
FileUtils.touch("#{out}/#{MARKER}")

GEM = 'identity_gem'

def run!(*cmd, chdir:)
  output, status = Open3.capture2e(*cmd, chdir:)
  raise "#{cmd.join(' ')} failed:\n#{output}" unless status.success?

  output
end

# A gem whose JavaScript takes preact as a peer. preact, not React: npm's React is CommonJS,
# which an unbundled page cannot load at all ("Dynamic require ... is not supported"), so the
# apps that unbundle React serve an ESM copy outside npm. The question is the same for any
# package: one real file through two links must be one module.
gem_root = File.join(out, 'identity_gem')
FileUtils.mkdir_p(gem_root)
File.write(File.join(gem_root, 'package.json'),
           JSON.generate('name' => "@rubygems/#{GEM}",
                         'peerDependencies' => { 'preact' => '^10.0.0' }))
File.write(File.join(gem_root, 'index.js'), "export * as preact from 'preact'\n")
roots = { GEM => File.realpath(gem_root) }

app = File.join(out, 'app')
FileUtils.mkdir_p(File.join(app, 'app'))
manifest = { 'name' => 'app', 'private' => true, 'dependencies' => { 'preact' => '10.26.9' } }
File.write(File.join(app, 'package.json'), JSON.generate(manifest))
StageA::Context.register_pnpm(app)
context = File.realpath(StageA::Context.write(app, GEM, roots.fetch(GEM)))
run!('pnpm', 'install', chdir: app)
app = File.realpath(app)

# The page, and its control: the control imports the app's preact by its link path, as an
# engine that did not resolve real paths would, so it should load preact twice.
link = '/node_modules/preact/dist/preact.module.js'
{ 'page' => 'preact', 'control' => link }.each do |name, specifier|
  File.write(File.join(app, "app/#{name}.js"), <<~JS)
    import * as preact from '#{specifier}'
    import { preact as fromGem } from '@rubygems/#{GEM}/index.js'

    window.identity = { same: preact.Component === fromGem.Component }
  JS
end

# Every module the page needs, built as the middleware would serve it.
site = File.join(out, 'site')
overrides = { RubyGems: roots, Bundle: false, Aliases: {}, External: [], Precompile: [],
              StageAContexts: { GEM => context } }
queue = ['/app/page.js', '/app/control.js']
built = {}
until queue.empty?
  url = queue.shift
  next if built[url]

  entry = url.delete_prefix('/')
  code = Proscenium::Builder.build_to_string(entry, root: app, **overrides)[:response]
  built[url] = true
  path = File.join(site, url)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, code)
  queue.concat(code.scan(%r{(?:from|import)\s*\(?\s*"(/[^"]+)"}).flatten)
end
%w[page control].each do |name|
  html = %(<script type="module" src="/app/#{name}.js"></script>)
  File.write(File.join(site, "#{name}.html"), html)
end

# Serve the site and load the page in Chromium.
probe = File.join(out, 'probe.cjs')
File.write(probe, <<~JS)
  const http = require('http'), fs = require('fs'), path = require('path')
  const { chromium } = require(#{playwright.to_json})
  const root = #{site.to_json}
  const server = http.createServer((req, res) => {
    const file = path.resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://x').pathname))
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file)) {
      res.writeHead(404)
      return res.end()
    }
    const type = file.endsWith('.html') ? 'text/html' : 'text/javascript'
    res.writeHead(200, { 'content-type': type })
    res.end(fs.readFileSync(file))
  }).listen(0, '127.0.0.1', async () => {
    const browser = await chromium.launch()
    const results = {}
    for (const name of ['page', 'control']) {
      const page = await browser.newPage()
      const errors = []
      page.on('pageerror', e => errors.push(e.message))
      await page.goto(`http://127.0.0.1:${server.address().port}/${name}.html`)
      await page.waitForFunction(() => window.identity, null, { timeout: 10000 }).catch(() => {})
      results[name] = { identity: await page.evaluate(() => window.identity), errors }
    }
    console.log(JSON.stringify(results))
    await browser.close()
    server.close()
  })
JS
result = JSON.parse(run!('node', probe, chdir: out).lines.last)

puts "preact URLs built: #{built.keys.grep(/preact/).join(', ')}"
result.each { |name, r| puts "#{name}: #{r.to_json}" }

# The page must share one preact, the control must load two, and neither may have failed.
expected = { 'page' => true, 'control' => false }
failures = expected.filter_map do |name, same|
  r = result.fetch(name)
  "#{name}: #{r.to_json}" unless r['errors'].empty? && r.dig('identity', 'same') == same
end
abort "identity probe failed:\n#{failures.join("\n")}" if failures.any?
puts 'identity probe passed'
