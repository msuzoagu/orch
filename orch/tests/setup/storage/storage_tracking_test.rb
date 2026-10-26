# frozen_string_literal: true

require 'test_helper'
require 'orch/setup/storage/manage_storage_tracking'

class StorageTrackingCommandDouble
  attr_reader :calls

  def initialize(results:)
    @results = results.dup
    @calls = []
  end

  def capture3(*arguments)
    @calls << arguments
    result = @results.shift
    raise(result) if result.is_a?(Exception)
    raise('Unexpected Git command') if result.nil?

    output, code, diagnostic = result
    [output, diagnostic || '', Struct.new(:exitstatus).new(code)]
  end
end

class StorageTrackingRootDouble
  def resolve(project_root:)
    raise(StoragePreparationError, 'Invalid root') if project_root == 'invalid'

    "#{project_root}/wr"
  end
end

class StorageTrackingOutputDouble
  attr_reader :lines

  def initialize
    @lines = []
  end

  def puts(line)
    @lines << line
  end
end

class StorageTrackingTest
  def initialize
    @checks = 0
    @project_root = '/workspace/project with spaces'
    @environment = {
      'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1'
    }
  end

  def run
    verify_checks
    verify_authorization
    verify_untracking
    verify_failures
    verify_entry_point
    verify_skill
    puts("PASS: #{@checks} storage-tracking assertions")
  end

  private

  def assert(condition, message)
    raise("FAIL: #{message}") unless condition

    @checks += 1
  end

  def assert_error(message)
    yield
  rescue StoragePreparationError => error
    assert(error.message.include?(message), 'failure diagnostic was lost')
  else
    raise('FAIL: expected failure was accepted')
  end

  def tracker(results)
    runner = StorageTrackingCommandDouble.new(results:)
    [StorageTracking.new(command_runner: runner), runner]
  end

  def expected_command(*arguments)
    [@environment, 'git', '-C', @project_root, *arguments]
  end

  def verify_checks
    paths = ['wr/Record.json', "wr/file with spaces\nand newline.md"]
    tracking, runner = tracker([["#{paths.join("\0")}\0", 0]])
    assert(tracking.tracked_paths(project_root: @project_root) == paths,
           'tracked filenames were split or altered')
    assert(runner.calls == [expected_command('ls-files', '-z', '--', 'wr/')],
           'tracking check was not repository scoped and read-only')
    tracking, runner = tracker([['', 0]])
    assert(tracking.tracked_paths(project_root: @project_root).empty?,
           'empty index result was rejected')
    assert(runner.calls.length == 1, 'empty check changed tracking')

    tracking, runner = tracker([])
    assert_error('absolute path') do
      tracking.tracked_paths(project_root: 'relative')
    end
    assert(runner.calls.empty?, 'invalid root launched Git')
    tracking, runner = tracker([["src/unrelated.rb\0", 0]])
    assert_error('outside wr/') do
      tracking.tracked_paths(project_root: @project_root)
    end
  end

  def verify_authorization
    [false, nil, 'yes', 1].each do |approval|
      tracking, runner = tracker([])
      assert_error('Human approval') do
        tracking.untrack(project_root: @project_root, authorized: approval)
      end
      assert(runner.calls.empty?, 'missing approval launched Git')
    end
  end

  def verify_untracking
    tracking, runner = tracker([["wr/Record.json\0", 0], ['', 0], ['', 0]])
    result = tracking.untrack(project_root: @project_root, authorized: true)
    assert(result == [],
           'approved untracking did not return the verified empty result')
    assert(runner.calls == [
      expected_command('ls-files', '-z', '--', 'wr/'),
      expected_command('rm', '-r', '--cached', '--', 'wr/'),
      expected_command('ls-files', '-z', '--', 'wr/')
    ], 'untracking deleted local files, expanded scope, or omitted rechecking')

    tracking, runner = tracker([['', 0]])
    result = tracking.untrack(project_root: @project_root, authorized: true)
    assert(result == [],
           'already untracked storage was rejected')
    assert(runner.calls.length == 1, 'already untracked storage was modified')
  end

  def verify_failures
    tracking, runner = tracker([['', 128, 'simulated Git failure']])
    assert_error('simulated Git failure') do
      tracking.tracked_paths(project_root: @project_root)
    end
    assert(runner.calls.length == 1, 'failed check retried or continued')

    tracking, runner = tracker([
      ["wr/Record.json\0", 0], ['', 1, 'staged changes prevent removal']
    ])
    assert_error('staged changes prevent removal') do
      tracking.untrack(project_root: @project_root, authorized: true)
    end
    assert(runner.calls.length == 2, 'failed removal was forced or retried')

    tracking, runner = tracker([
      ["wr/Record.json\0", 0], ['', 0], ["wr/remaining.md\0", 0]
    ])
    assert_error('Git still tracks storage paths') do
      tracking.untrack(project_root: @project_root, authorized: true)
    end
    assert(runner.calls.length == 3, 'remaining tracking triggered a retry')

    tracking, runner = tracker([
      ["wr/Record.json\0", 0], ['', 0], ['', 128, 'recheck failed']
    ])
    assert_error('recheck failed') do
      tracking.untrack(project_root: @project_root, authorized: true)
    end
    assert(runner.calls.length == 3, 'failed recheck triggered reversion')

    tracking, runner = tracker([IOError.new('simulated execution failure')])
    assert_error('IOError: simulated execution failure') do
      tracking.tracked_paths(project_root: @project_root)
    end
    assert(runner.calls.length == 1, 'execution failure was retried')
  end

  def run_entry(arguments, results)
    tracking, runner = tracker(results)
    output = StorageTrackingOutputDouble.new
    errors = StorageTrackingOutputDouble.new
    entry = StorageTrackingEntryPoint.new(
      tracking:, root_resolver: StorageTrackingRootDouble.new, output:, errors:
    )
    [entry.run(arguments:), output.lines, errors.lines, runner.calls]
  end

  def verify_entry_point
    code, output, errors, calls = run_entry(
      ['check', @project_root], [["wr/Record.json\0", 0]]
    )
    assert(code == 0 && JSON.parse(output.fetch(0)) == ['wr/Record.json'],
           'check CLI did not return a JSON path array')
    assert(errors.empty? && calls.length == 1, 'check CLI changed the index')

    code, output, errors, calls = run_entry(['untrack', @project_root], [])
    assert(code == 1 && output.empty?, 'unapproved CLI reported success')
    assert(errors.fetch(0).include?('Human approval') && calls.empty?,
           'unapproved CLI changed the index')

    code, output, errors, calls = run_entry(
      ['untrack', @project_root, '--approved'],
      [["wr/Record.json\0", 0], ['', 0], ['', 0]]
    )
    assert(code == 0 && JSON.parse(output.fetch(0)) == [],
           'approved CLI did not return a verified empty array')
    assert(errors.empty? && calls.length == 3,
           'approved CLI skipped verification')

    invalid_arguments = [
      [], ['delete', @project_root], ['untrack', @project_root, '--force']
    ]
    invalid_arguments.each do |args|
      code, output, errors, calls = run_entry(args, [])
      assert(code == 2 && output.empty? && !errors.empty? && calls.empty?,
             'invalid CLI arguments launched Git')
    end
    code, output, errors, calls = run_entry(['check', 'invalid'], [])
    assert(code == 1 && output.empty? && !errors.empty? && calls.empty?,
           'invalid project root launched Git')
    code, output, errors, calls = run_entry(
      ['untrack', @project_root, '--approved'],
      [["wr/Record.json\0", 0], ['', 1, 'removal failed']]
    )
    assert(code == 1 && output.empty? &&
           errors.fetch(0).include?('removal failed'),
           'failed CLI removal reported success')
    assert(calls.length == 2, 'failed CLI removal continued')
  end

  def verify_skill
    skill = File.read(
      File.join(OrchTestPaths::PLUGIN_ROOT, 'skills/setup/SKILL.md')
    )
    ready_condition = 'If storage exists, is writable, ignored, and untracked'
    assert(skill.index('check "<project-root>"') <
           skill.index(ready_condition),
           'Setup declared ready without checking tracking')
    assert(skill.include?('End the turn and wait for an explicit answer.'),
           'Setup does not wait for untracking approval')
    manual_only = 'Do not run it on their behalf.'
    assert(skill.include?('On **No**') && skill.include?(manual_only),
           'Setup does not stop for manual untracking')
    pending = 'answer remains pending; do not change files or the Git index.'
    assert(skill.include?('No answer or an unclear') && skill.include?(pending),
           'pending approval permits index changes')
    assert(skill.include?('untrack "<project-root>" --approved'),
           'Setup does not invoke the approved helper')
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    StorageTrackingTest.new.run
  rescue StandardError => error
    warn("Storage tracking tests failed: #{error.class}: #{error.message}")
    exit(1)
  end
end
