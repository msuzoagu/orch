# frozen_string_literal: true

require 'test_helper'
require 'orch/setup/git/git_ignore_error'
require 'orch/setup/git/git_ignore_checker'

# A test double replaces the real command runner with controlled results.
# It records calls so the tests can inspect arguments without running Git,
# creating a repository, or reading the user's Git configuration.
class GitIgnoreCommandDouble
  attr_reader :calls

  # Configure the result or exception that capture3 will simulate.
  # Globals: None.
  # Instance variables: Sets @status, @diagnostic, @error, and @calls.
  # Arguments:
  #   exit_status: Simulated Git exit code; unused when error is supplied.
  #   diagnostic: Simulated standard error text; defaults to empty.
  #   error: Optional exception to raise instead of returning a result.
  # Outputs: None.
  # Returns: No public result; .new returns the configured test double.
  def initialize(exit_status:, diagnostic: '', error: nil)
    @status = Struct.new(:exitstatus).new(exit_status)
    @diagnostic = diagnostic
    @error = error
    @calls = []
  end

  # Record a command attempt, then return the configured result or raise.
  # Recording before raising lets failure tests also check the attempted
  # command and confirm that execution was not retried.
  # Globals: None.
  # Instance variables: Reads @error, @diagnostic, @status; appends @calls.
  # Arguments: The environment hash followed by command arguments.
  # Outputs: None; the returned strings simulate process output.
  # Returns: [empty standard output, diagnostic text, exit-status object].
  # Raises: The configured exception, if supplied.
  def capture3(*arguments)
    @calls << arguments
    raise(@error) if @error

    ['', @diagnostic, @status]
  end
end

# Unit tests for the checker's result handling and command construction.
# These do not establish whether a real repository ignores wr/ or whether
# real Git respects the supplied configuration settings. Git is simulated.
class GitIgnoreCheckerTest
  # Start the assertion count and choose a project path containing spaces.
  # That path need not exist: it tests argument handling, not filesystem
  # access. Its spaces help expose accidental splitting of one argument.
  # Globals: None.
  # Instance variables: Sets @checks and @project_root.
  # Arguments: None.
  # Outputs: None.
  # Returns: No public result; .new returns the test instance.
  def initialize
    @checks = 0
    @project_root = '/workspace/project with spaces'
  end

  # Exercise four outcomes: ignored, not ignored, Git command failure,
  # and an exception while attempting execution. Each case also checks
  # command arguments, configuration settings, and environment preservation.
  # Globals: ENV is inspected by the cases; it must remain unchanged.
  # Instance variables: Uses @project_root; increments @checks via assert.
  # Arguments: None.
  # Outputs: Writes the passing assertion count to standard output.
  # Returns: nil after success; an assertion failure raises and stops tests.
  def run
    verify_result(exit_status: 0, expected: true)
    verify_result(exit_status: 1, expected: false)
    verify_command_failure
    verify_execution_failure
    puts("PASS: #{@checks} Git-ignore checker assertions")
  end

  private

  # Count a passing check, or stop immediately with its failure message.
  # Globals: None.
  # Instance variables: Increments @checks only when the condition passes.
  # Arguments: condition is the check result; message explains a failure.
  # Outputs: None; the script's entry point reports raised failures.
  # Returns: The updated assertion count.
  # Raises: RuntimeError when the condition is false or nil.
  def assert(condition, message)
    raise("FAIL: #{message}") unless condition

    @checks += 1
  end

  # Check that a completed Git check becomes the correct Boolean result.
  # Exit code 0 means ignored; 1 means not ignored, not a command failure.
  # Also confirm the command is correct and does not alter the Ruby
  # process's environment; isolation settings belong to the command only.
  # Globals: Reads ENV before and after the call; requires it unchanged.
  # Instance variables: Reads @project_root; increments @checks via assert.
  # Arguments: exit_status is the simulated code; expected is the Boolean.
  # Outputs: None.
  # Returns: No meaningful result; a failed check raises.
  def verify_result(exit_status:, expected:)
    runner = GitIgnoreCommandDouble.new(exit_status:)
    checker = GitIgnoreChecker.new(command_runner: runner)
    environment_before = ENV.to_h
    assert(
      checker.ignored?(project_root: @project_root) == expected,
      'wrong ignore result'
    )
    verify_command(runner)
    assert(ENV.to_h == environment_before, 'parent environment changed')
  end

  # Simulate Git returning a fatal status, rather than a valid ignore result.
  # Require GitIgnoreError to retain the diagnostic and project path so
  # callers can report what failed and where. A Git failure must not become
  # false, trigger another attempt, or change the Ruby process's environment.
  # Globals: Reads ENV before and after the call; requires it unchanged.
  # Instance variables: Reads @project_root; increments @checks via assert.
  # Arguments: None.
  # Outputs: None.
  # Returns: No meaningful result; missing errors or failed checks raise.
  def verify_command_failure
    diagnostic = 'fatal: configuration could not be read'
    runner = GitIgnoreCommandDouble.new(exit_status: 128, diagnostic:)
    checker = GitIgnoreChecker.new(command_runner: runner)
    environment_before = ENV.to_h
    begin
      checker.ignored?(project_root: @project_root)
    rescue GitIgnoreError => error
      assert(error.message.include?(diagnostic), 'Git diagnostic was lost')
      assert(error.message.include?(@project_root), 'project context was lost')
    else
      raise('FAIL: Git failure was treated as an ignore result')
    end
    assert(
      ENV.to_h == environment_before,
      'failed ignore check changed the parent environment'
    )
    verify_command(runner)
  end

  # Simulate the runner raising IOError without returning a Git result.
  # Require GitIgnoreError to preserve the original error type, message,
  # and project path. This distinguishes execution failure from "not ignored"
  # and keeps the cause available to callers. Also require no retry or
  # change to the Ruby process's environment on this exception path.
  # Globals: Reads ENV before and after the call; requires it unchanged.
  # Instance variables: Reads @project_root; increments @checks via assert.
  # Arguments: None.
  # Outputs: None.
  # Returns: No meaningful result; missing errors or failed checks raise.
  def verify_execution_failure
    diagnostic = 'command execution failed'
    runner = GitIgnoreCommandDouble.new(
      exit_status: nil, error: IOError.new(diagnostic)
    )
    checker = GitIgnoreChecker.new(command_runner: runner)
    environment_before = ENV.to_h
    begin
      checker.ignored?(project_root: @project_root)
    rescue GitIgnoreError => error
      assert(
        error.message.include?('IOError'),
        'execution error was lost'
      )
      assert(
        error.message.include?(diagnostic),
        'original execution error message was lost'
      )
      assert(
        error.message.include?(@project_root),
        'execution error omitted the project path'
      )
    else
      raise('FAIL: execution failure was ignored')
    end
    assert(
      ENV.to_h == environment_before,
      'failed ignore check changed the parent environment'
    )
    verify_command(runner)
  end

  # Check the command requested in each of the four simulated outcomes.
  # Require one attempt and both configuration-isolation settings. Inspect
  # separate arguments so a joined string cannot hide a split project path,
  # a different Git operation, or an extra target outside the intended scope.
  # Globals: None; inspects the recorded environment hash instead of ENV.
  # Instance variables: Reads @project_root; increments @checks via assert.
  # Arguments: runner is the test double holding the attempted command.
  # Outputs: None.
  # Returns: No meaningful result; a failed command check raises.
  def verify_command(runner)
    assert(runner.calls.length == 1, 'Git command was retried unnecessarily')
    environment, *command = runner.calls.fetch(0)

    # Apply configuration isolation to this command, not the parent process.
    # Other environment settings are allowed; these two must be present.
    assert(environment['GIT_CONFIG_NOSYSTEM'] == '1', 'System config isolation missing')
    assert(environment['GIT_CONFIG_GLOBAL'] == '/dev/null', 'Global config isolation missing')

    # -C selects the repository; -- ends option parsing before the wr/ target.
    # Exact argument positions and length preserve boundaries and scope.
    assert(command[0] == 'git', 'Executable must be git')
    assert(command[1] == '-C', 'Context flag must be -C')
    assert(command[2] == @project_root, 'Project root argument boundary was broken or split')
    assert(command[3] == 'check-ignore', 'Operation must be check-ignore')
    assert(command[4] == '--', 'Double-dash boundary marker is missing')
    assert(command[5] == 'wr/', 'Target folder argument boundary was broken or split')
    assert(command.length == 6, "Command contains unexpected trailing arguments: #{command[6..]}")
  end

end

# Run only when invoked as a script; requiring this file defines the tests
# without executing them. Report a failure on standard error and exit 1.
if $PROGRAM_NAME == __FILE__
  begin
    GitIgnoreCheckerTest.new.run
  rescue StandardError => error
    warn("Git-ignore tests failed: #{error.class}: #{error.message}")
    exit(1)
  end
end
