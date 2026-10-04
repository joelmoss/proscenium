# frozen_string_literal: true

require 'bundler'
require 'fileutils'
require 'open3'
require 'rubygems/package'

module StageA
  # Installs the Stage A fixture gems the way an app gets them: genuinely, through Bundler, into a
  # throwaway BUNDLE_PATH that is then made read-only. Nothing here loads Rails.
  #
  # The archive gems are built locally and installed from the app's vendor/cache with
  # `bundle install --local`, so no gem index or network is involved. stage_a_hue_shape is a Git
  # source, as hue is: its package.json is not in `spec.files`, and only a Git checkout keeps it.
  module Bundle
    GEMS = File.expand_path('gems', __dir__)
    ARCHIVES = %w[stage_a_assets stage_a_widget_a stage_a_widget_b].freeze
    GIT = 'stage_a_hue_shape'

    # The repository's own gem_npm fixture (string-length ^6.0.0). Its gemspec lists no files and
    # does not opt in, and the dummy app loads it as a path gem, so the archive gets both here
    # rather than in the gemspec.
    GEM_NPM = File.expand_path('../../../fixtures/dummy/vendor/gem_npm', __dir__)

    module_function

    # Installs every fixture gem under `dir` and returns `{ name => installed root }`.
    def install(dir)
      app = File.join(dir, 'app')
      cache = File.join(app, 'vendor', 'cache')
      FileUtils.mkdir_p(cache)

      ARCHIVES.each { |name| build(File.join(GEMS, name), cache) }
      build(GEM_NPM, cache) do |spec|
        spec.files = Dir.children(GEM_NPM).reject { |f| f.end_with?('.gemspec') }.sort
        spec.metadata['proscenium.dependencies'] = 'true'
      end

      File.write(File.join(app, 'Gemfile'), gemfile(git_repo(dir)))

      bundle(app, dir, 'install', '--local')
      roots = bundle(app, dir, 'list', '--paths').lines(chomp: true)
                                                 .to_h { |path| [gem_name(path), path] }
                                                 .except('bundler')

      # Read-only, as a shared or system gem install is. Bundler reinstalls nothing into it.
      FileUtils.chmod_R('a-w', File.join(dir, 'bundle'))

      roots
    end

    # Undoes the read-only bit so the directory can be removed (Windows refuses otherwise).
    def writable!(dir)
      bundle = File.join(dir, 'bundle')
      FileUtils.chmod_R('u+w', bundle) if File.exist?(bundle)
    end

    def build(source, cache)
      spec = Gem::Specification.load(Dir[File.join(source, '*.gemspec')].first)
      yield spec if block_given?

      file = Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
        Dir.chdir(source) { Gem::Package.build(spec) }
      end
      FileUtils.mv(File.join(source, file), cache)
    end

    # A local Git repository holding stage_a_hue_shape, committed so Bundler can lock a revision.
    def git_repo(dir)
      repo = File.join(dir, GIT)
      FileUtils.cp_r(File.join(GEMS, GIT), repo)
      git(repo, 'init', '-q')
      git(repo, 'add', '-A')
      git(repo, '-c', 'user.name=Stage A', '-c', 'user.email=stage-a@example.com',
          'commit', '-q', '-m', 'stage_a_hue_shape')
      repo
    end

    def gemfile(repo)
      <<~GEMFILE
        source 'https://rubygems.org'

        #{ARCHIVES.map { |name| "gem '#{name}'" }.join("\n")}
        gem '#{GIT}', git: '#{repo}'

        # A group a production install leaves out (C32).
        gem 'gem_npm', group: :development
      GEMFILE
    end

    # The environment that selects the fixture app's bundle, installed under `dir`.
    def env(dir)
      { 'BUNDLE_GEMFILE' => File.join(dir, 'app', 'Gemfile'),
        'BUNDLE_PATH' => File.join(dir, 'bundle'),
        'BUNDLE_APP_CONFIG' => File.join(dir, '.bundle'),
        'BUNDLE_DISABLE_SHARED_GEMS' => 'true' }
    end

    def bundle(app, dir, *args)
      out, status = Bundler.with_unbundled_env do
        Open3.capture2e(env(dir), 'bundle', *args, chdir: app)
      end
      raise "bundle #{args.join(' ')} failed:\n#{out}" unless status.success?

      out
    end

    def git(repo, *args)
      out, status = Open3.capture2e('git', *args, chdir: repo)
      raise "git #{args.join(' ')} failed:\n#{out}" unless status.success?
    end

    # `bundle list --paths` prints installed roots; a Git gem's ends in `<name>-<revision>`.
    def gem_name(path)
      base = File.basename(path)
      [*ARCHIVES, 'gem_npm', GIT, 'bundler'].find { |name| base.start_with?("#{name}-") } || base
    end
  end
end
