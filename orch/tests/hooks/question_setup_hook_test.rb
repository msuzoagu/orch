# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'orch/hooks/question_setup_hook'

class QuestionSetupHookTest
  def initialize
    @plugin_root = OrchTestPaths::PLUGIN_ROOT
    @workspace_root = OrchTestPaths::WORKSPACE_ROOT
    @setup_path = File.join(@plugin_root, 'skills', 'setup', 'SKILL.md')
    @hook = QuestionSetupHook.new(setup_skill_path: @setup_path)
    @checks = 0
  end

  def run
    verify_matching
    verify_nonmatching
    verify_invalid_payloads
    verify_invocation
    puts("PASS: #{@checks} Question Setup hook assertions")
  end

  private

  def assert(condition, message)
    raise("FAIL: #{message}") unless condition

    @checks += 1
  end

  def payload(prompt)
    { 'hook_event_name' => 'UserPromptSubmit', 'prompt' => prompt }
  end

  def verify_response(result, setup_path)
    assert(result.keys == ['hookSpecificOutput'], 'wrong response envelope')
    output = result.fetch('hookSpecificOutput')
    assert(output.fetch('hookEventName') == 'UserPromptSubmit', 'wrong event')
    context = output.fetch('additionalContext')
    assert(context.include?(setup_path.dump), 'wrong installed Setup path')
    assert(context.include?('execute the Setup skill workflow'), 'no execution')
    assert(
      context.include?('authorization, waiting, and stopping'), 'no waiting'
    )
    assert(
      context.include?('Preserve the supplied Question verbatim'), 'no text'
    )
  end

  def verify_matching
    [
      '@orch:question',
      '@orch:question tell me about this project',
      " \t@orch:question\nWhy does CSV upload fail?"
    ].each do |prompt|
      original = prompt.dup
      verify_response(@hook.call(payload: payload(prompt)), @setup_path)
      assert(prompt == original, 'Question text was modified')
    end

    first = @hook.call(payload: payload('@orch:question'))
    second = @hook.call(payload: payload('@orch:question'))
    assert(first == second, 'a repeated invocation skipped Setup')
  end

  def verify_nonmatching
    [
      '', 'tell me about this project', '@orch:setup', '@other:question',
      '@orch:questionnaire', 'Explain @orch:question',
      '`@orch:question`', "\"@orch:question\"", '@orch:question:extra'
    ].each do |prompt|
      assert(@hook.call(payload: payload(prompt)).nil?, 'nonmatch triggered')
    end
    other_event = { 'hook_event_name' => 'SessionStart' }
    assert(@hook.call(payload: other_event).nil?, 'other event triggered')
  end

  def verify_invalid_payloads
    [nil, [], {}, { 'hook_event_name' => nil },
     { 'hook_event_name' => 'UserPromptSubmit' }, payload(nil),
     payload(42)].each do |invalid|
      begin
        @hook.call(payload: invalid)
      rescue ArgumentError, KeyError
        assert(true, 'invalid payload rejected')
      else
        raise('FAIL: invalid payload accepted')
      end
    end
  end

  def hook_command(plugin_root)
    manifest = JSON.parse(File.read(File.join(plugin_root, 'plugin.json')))
    extension = manifest.fetch('extensions').fetch('com.openai')
    relative_path = extension.fetch('hooks')
    assert(relative_path == './hooks/hooks.json', 'wrong manifest reference')
    configuration = JSON.parse(File.read(File.join(plugin_root, relative_path)))
    events = configuration.fetch('hooks')
    assert(events.keys == ['UserPromptSubmit'], 'unexpected registered event')
    handler = events.fetch('UserPromptSubmit').fetch(0).fetch('hooks').fetch(0)
    assert(handler.fetch('type') == 'command', 'wrong hook type')
    handler.fetch('command').gsub('${PLUGIN_ROOT}', plugin_root)
  end

  def invoke(plugin_root, target, input)
    # Execute the trusted configured shell command as Codex does.
    Open3.capture3(
      '/bin/sh', '-c', hook_command(plugin_root),
      stdin_data: input, chdir: target
    )
  end

  def verify_invocation
    fixture_root = File.join(@workspace_root, '.unclassified')
    FileUtils.mkdir_p(fixture_root)
    Dir.mktmpdir('question-hook-', fixture_root) do |fixture|
      target = File.join(fixture, 'target project')
      FileUtils.mkdir_p(target)
      verify_command(@plugin_root, target)
      verify_relocation(fixture, target)
      assert(Dir.children(target).empty?, 'hook wrote target project files')
    end
  end

  def verify_command(plugin_root, target)
    stdout, stderr, status = invoke(
      plugin_root, target, JSON.generate(payload('@orch:question explain CSV'))
    )
    assert(status.success?, "hook invocation failed: #{stderr}")
    assert(stderr.empty?, 'successful invocation emitted diagnostics')
    verify_response(
      JSON.parse(stdout), File.join(plugin_root, 'skills', 'setup', 'SKILL.md')
    )

    stdout, stderr, status = invoke(
      plugin_root, target, JSON.generate(payload('ordinary prompt'))
    )
    assert(status.success?, 'nonmatching invocation failed')
    assert(stdout.empty? && stderr.empty?, 'nonmatch produced output')

    ['not JSON', JSON.generate([]), JSON.generate(payload(nil))].each do |input|
      stdout, stderr, status = invoke(plugin_root, target, input)
      assert(
        status.exitstatus == 2, 'invalid input did not return blocking code'
      )
      assert(stdout.empty?, 'invalid input produced a success response')
      assert(!stderr.empty?, 'invalid input had no blocking reason')
    end

    stdout, stderr, status = Open3.capture3(
      '/bin/sh', File.join(plugin_root, 'scripts', 'ruby_launcher.sh'),
      '-e', 'require(ARGV.fetch(0))',
      File.join(plugin_root, 'hooks', 'question_setup.rb'), chdir: target
    )
    assert(status.success?, "requiring entry point failed: #{stderr}")
    assert(
      stdout.empty? && stderr.empty?, 'requiring entry point executed hook'
    )

    stdout, stderr, status = Open3.capture3(
      '/bin/sh', File.join(plugin_root, 'scripts', 'ruby_launcher.sh'),
      File.join(plugin_root, 'hooks', 'question_setup.rb'), 'unexpected',
      chdir: target
    )
    assert(status.exitstatus == 2, 'entry point accepted command arguments')
    assert(stdout.empty?, 'invalid arguments produced a success response')
    assert(stderr.include?('Usage:'), 'invalid arguments had no diagnostic')
  end

  def verify_relocation(fixture, target)
    relocated = File.join(fixture, 'installed plugin')
    FileUtils.mkdir_p(relocated)
    %w[hooks lib scripts skills].each do |directory|
      FileUtils.cp_r(File.join(@plugin_root, directory), relocated)
    end
    FileUtils.cp(File.join(@plugin_root, 'plugin.json'), relocated)
    File.symlink(
      File.join(@plugin_root, 'runtime'), File.join(relocated, 'runtime')
    )
    verify_command(relocated, target)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    QuestionSetupHookTest.new.run
  rescue StandardError => error
    warn("Question Setup hook tests failed: #{error.class}: #{error.message}")
    exit(1)
  end
end
