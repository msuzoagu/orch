# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'

class RuntimeDeliveryTest
  def initialize
    @plugin_root = OrchTestPaths::PLUGIN_ROOT
    @workspace_root = OrchTestPaths::WORKSPACE_ROOT
    @configuration = JSON.parse(
      File.read(File.join(@plugin_root, 'runtime', 'runtime.json'))
    )
    @checks = 0
  end

  def run
    @configuration.fetch('TestGems').each do |name, version|
      assert(
        Gem.loaded_specs.fetch(name).version.to_s == version, "wrong #{name}"
      )
    end
    fixture_root = File.join(@workspace_root, '.unclassified')
    FileUtils.mkdir_p(fixture_root)

    Dir.mktmpdir('runtime-delivery-', fixture_root) do |fixture|
      target = File.join(fixture, 'another project')
      FileUtils.mkdir_p(target)
      verify_diagnostic(@plugin_root, target)
      verify_diagnostic(@plugin_root, target, hostile_environment(fixture))
      verify_arguments(target)
      verify_exit_status(target)
      verify_library_loading(target)
      verify_missing_runtime(fixture, target)
      verify_relocation(fixture, target)
      assert(Dir.children(target).empty?, 'target project was modified')
    end

    puts("PASS: #{@checks} runtime-delivery assertions")
  end

  private

  def assert(condition, message)
    raise("FAIL: #{message}") unless condition

    @checks += 1
  end

  def invoke(plugin_root, target, *arguments, environment: {})
    launcher = File.join(plugin_root, 'scripts', 'ruby_launcher.sh')
    Open3.capture3(
      environment, '/bin/sh', launcher, *arguments, chdir: target
    )
  end

  def verify_diagnostic(plugin_root, target, environment = {})
    diagnostic = File.join(
      plugin_root, 'scripts', 'runtime_delivery_diagnostic.rb'
    )
    stdout, stderr, status = invoke(
      plugin_root, target, diagnostic, environment: environment
    )
    assert(status.success?, "diagnostic failed: #{stderr}")
    assert(stderr.empty?, "unexpected diagnostic errors: #{stderr}")
    result = JSON.parse(stdout)
    runtime = File.realpath(
      File.join(plugin_root, 'runtime', @configuration.fetch('Directory'))
    )
    gem_root = File.join(runtime, 'lib', 'ruby', 'gems', '4.0.0')
    assert(result.fetch('RuntimeRoot') == runtime, 'wrong runtime root')
    assert(
      result.fetch('Executable') == File.join(runtime, 'bin', 'ruby'),
      'wrong Ruby executable'
    )
    assert(
      result.fetch('RubyVersion') == @configuration.fetch('RubyVersion'),
      'wrong Ruby version'
    )
    assert(result.fetch('GemPaths') == [gem_root], 'external gem search path')
    assert(result.fetch('WorkingDirectory') == target, 'caller directory lost')
    assert(result.fetch('JSONRoundTrip') == { 'ready' => true }, 'JSON failed')
    @configuration.fetch('HelperGems').each do |name, version|
      assert(
        result.fetch('GemVersions').fetch(name) == version, "wrong #{name}"
      )
    end
    verify_bundled_paths(result.fetch('LoadedRubyFiles'), runtime)
    verify_bundled_paths(result.fetch('NonSystemNativeLibraries'), runtime)
  end

  def verify_bundled_paths(paths, runtime)
    assert(!paths.empty?, 'dependency inspection returned no paths')
    external = paths.reject { |path| path.start_with?("#{runtime}/") }
    assert(external.empty?, "external dependencies: #{external.join(', ')}")
  end

  def hostile_environment(fixture)
    missing = File.join(fixture, 'must-not-load')
    {
      'PATH' => '/nonexistent',
      'GEM_HOME' => missing,
      'GEM_PATH' => missing,
      'GEM_SPEC_CACHE' => missing,
      'RUBYOPT' => "-r#{missing}",
      'RUBYLIB' => missing,
      'RUBYGEMS_GEMDEPS' => missing,
      'BUNDLER_SETUP' => missing,
      'BUNDLE_BIN_PATH' => missing,
      'BUNDLE_GEMFILE' => missing,
      'BUNDLE_PATH' => missing,
      'BUNDLE_APP_CONFIG' => missing
    }
  end

  def verify_arguments(target)
    stdout, stderr, status = invoke(
      @plugin_root, target, '-e', 'puts(ARGV.fetch(0))',
      'an argument with spaces'
    )
    assert(status.success?, "argument forwarding failed: #{stderr}")
    assert(stdout == "an argument with spaces\n", 'argument changed')
    assert(stderr.empty?, 'argument test produced diagnostics')
  end

  def verify_exit_status(target)
    stdout, stderr, status = invoke(
      @plugin_root, target, '-e', 'warn("expected failure"); exit(7)'
    )
    assert(status.exitstatus == 7, 'helper exit status was lost')
    assert(stdout.empty?, 'failed helper printed success')
    assert(stderr == "expected failure\n", 'helper diagnostics were lost')
    diagnostic = File.join(
      @plugin_root, 'scripts', 'runtime_delivery_diagnostic.rb'
    )
    stdout, stderr, status = invoke(
      @plugin_root, target, diagnostic, 'unexpected'
    )
    assert(status.exitstatus == 1, 'diagnostic accepted invalid input')
    assert(stdout.empty?, 'invalid diagnostic printed success')
    assert(
      stderr.include?('ArgumentError'), 'diagnostic error was not identified'
    )
  end

  #######################################################################
  # Verify startup reports a missing runtime directory or Ruby executable.
  # Include valid platform configurations so an earlier configuration
  # failure cannot satisfy either case. Require exit status 78, empty
  # STDOUT, and an error identifying the intended missing item.
  # Globals:
  #   None.
  # Instance variables:
  #   @plugin_root (read): Source of the launcher and configurations.
  #   @configuration (read): Identifies the bundled runtime directory.
  #   @checks (updated through assert): Count of passing assertions.
  # Arguments:
  #   fixture: Workspace directory for disposable plugin files.
  #   target: Working directory used when invoking the launcher.
  # Outputs:
  #   Captures launcher STDOUT and STDERR; prints nothing on success.
  # Returns:
  #   No meaningful value; raises RuntimeError if an assertion fails.
  #######################################################################
  def verify_missing_runtime(fixture, target)
    missing_plugin = File.join(fixture, 'missing-runtime-plugin')
    FileUtils.mkdir_p(File.join(missing_plugin, 'scripts'))
    FileUtils.cp(
      File.join(@plugin_root, 'scripts', 'ruby_launcher.sh'),
      File.join(missing_plugin, 'scripts', 'ruby_launcher.sh')
    )
    FileUtils.cp_r(
      File.join(@plugin_root, 'scripts', 'runtime-configs'),
      File.join(missing_plugin, 'scripts')
    )
    runtime = File.join(
      missing_plugin, 'runtime', @configuration.fetch('Directory')
    )

    # The configuration exists, but the directory it identifies does not.
    stdout, stderr, status = invoke(missing_plugin, target, '--version')
    assert(status.exitstatus == 78, 'missing runtime returned wrong status')
    assert(stdout.empty?, 'missing runtime printed a Ruby version')
    assert(
      stderr.include?("runtime directory not found: #{runtime}"),
      "missing runtime was not identified: #{stderr}"
    )

    # Supply the runtime directory while leaving its Ruby file absent.
    FileUtils.mkdir_p(runtime)
    executable = File.join(runtime, 'bin', 'ruby')
    stdout, stderr, status = invoke(missing_plugin, target, '--version')
    assert(status.exitstatus == 78, 'missing Ruby returned wrong status')
    assert(stdout.empty?, 'missing executable printed a Ruby version')
    assert(
      stderr.include?("Ruby executable not found: #{executable}"),
      "missing Ruby executable was not identified: #{stderr}"
    )
  end

  def verify_library_loading(target)
    diagnostic = File.join(
      @plugin_root, 'scripts', 'runtime_delivery_diagnostic.rb'
    )
    stdout, stderr, status = invoke(
      @plugin_root, target, '-e', 'require(ARGV.fetch(0))', diagnostic
    )
    assert(status.success?, "requiring diagnostic failed: #{stderr}")
    assert(stdout.empty?, 'requiring diagnostic ran its entry point')
    assert(stderr.empty?, 'requiring diagnostic produced errors')
  end

  def verify_relocation(fixture, target)
    relocated = File.join(fixture, 'client cache', 'orch')
    portable = File.join(relocated, 'runtime', 'portable-ruby')
    FileUtils.mkdir_p(portable)
    FileUtils.cp_r(File.join(@plugin_root, 'scripts'), relocated)
    FileUtils.cp(File.join(@plugin_root, 'plugin.json'), relocated)
    FileUtils.cp(
      File.join(@plugin_root, 'runtime', 'runtime.json'),
      File.join(relocated, 'runtime', 'runtime.json')
    )
    FileUtils.cp_r(
      File.join(@plugin_root, 'runtime', @configuration.fetch('Directory')),
      portable
    )
    verify_diagnostic(relocated, target, hostile_environment(fixture))
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    RuntimeDeliveryTest.new.run
  rescue StandardError => error
    warn("Runtime delivery tests failed: #{error.class}: #{error.message}")
    exit(1)
  end
end
