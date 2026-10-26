# frozen_string_literal: true

# run integration tests directly via:
#   /bin/sh orch/scripts/ruby_launcher.sh \
#    -I orch/tests \
#    orch/tests/setup/storage/storage_preparation_integration_test.rb
# this to get around the restrictions (see AGENTS.md)

require 'test_helper'
require 'fileutils'
require 'forwardable'
require 'open3'
require 'tmpdir'
require 'orch/setup/git/git_ignore_error'
require 'orch/setup/git/git_ignore_checker'
require 'orch/setup/git/git_ignore_manager'

class GitIgnoreReplacementFilesystem
  extend Forwardable

  attr_reader :open_calls

  def_delegators :@filesystem, :directory?, :symlink?, :exist?, :file?,
                 :readable?, :binread, :lstat

  def initialize(filesystem:, before_open: nil, after_open: nil)
    @filesystem = filesystem
    @before_open = before_open
    @after_open = after_open
    @open_calls = 0
  end

  def open(path, *arguments)
    @open_calls += 1
    @before_open.call(path) if @before_open
    @filesystem.open(path, *arguments) do |file|
      @after_open.call(path) if @after_open
      yield file
    end
  end
end

class GitIgnoreManagerIntegrationTest
  def initialize(workspace_root:, command_runner:)
    @workspace_root = workspace_root
    @command_runner = command_runner
    @environment = {
      'GIT_CONFIG_GLOBAL' => '/dev/null',
      'GIT_CONFIG_NOSYSTEM' => '1',
      'GIT_AUTHOR_NAME' => 'Orch Integration Test',
      'GIT_AUTHOR_EMAIL' => 'orch-test@example.invalid',
      'GIT_COMMITTER_NAME' => 'Orch Integration Test',
      'GIT_COMMITTER_EMAIL' => 'orch-test@example.invalid'
    }
  end

  def run
    parent = File.join(@workspace_root, '.unclassified')
    FileUtils.mkdir_p(parent)
    Dir.mktmpdir('git-ignore-replacement-', parent) do |root|
      @fixture_root = root
      verify_symlink_before_open
      verify_symlink_after_open
      verify_regular_file_before_open
      verify_regular_file_after_open
      verify_concurrent_creation
      verify_missing_file_creation
      verify_real_git_exclusion
    end
    puts('PASS: Git-ignore replacement regressions and real-Git exclusion')
  end

  # Also serves as the injected Git command runner for the real checker.
  def capture3(environment, *command)
    result = @command_runner.capture3(@environment.merge(environment), *command)
    if result.fetch(1).match?(/Operation not permitted|Permission denied/i)
      raise("Permission block running #{command.inspect}: #{result.fetch(1)}")
    end

    result
  end

  private

  def assert(condition, message)
    raise("FAIL: #{message}") unless condition
  end

  def git(root, *arguments)
    output, diagnostic, status = capture3({}, 'git', '-C', root, *arguments)
    raise("Fixture Git #{arguments.inspect}: #{diagnostic}") unless
      status.success?

    output
  end

  def fixture(name, contents: "existing-rule\n")
    root = File.join(@fixture_root, name)
    Dir.mkdir(root)
    git(root, 'init', '--quiet', '--template=')
    File.binwrite(File.join(root, 'project.txt'), "preserve project\n")
    git(root, 'add', '--', 'project.txt')
    git(root, '-c', 'commit.gpgsign=false', 'commit', '--quiet',
        '-m', 'Create disposable ignore fixture')
    path = File.join(root, '.gitignore')
    File.binwrite(path, contents) unless contents.nil?
    [root, path]
  end

  def snapshot(root)
    [
      File.binread(File.join(root, '.git/index')),
      git(root, 'rev-parse', 'HEAD'),
      git(root, 'symbolic-ref', 'HEAD')
    ]
  end

  def manager(filesystem)
    GitIgnoreManager.new(
      filesystem:, ignore_checker: GitIgnoreChecker.new(command_runner: self)
    )
  end

  def rejected(root, filesystem)
    baseline = snapshot(root)
    begin
      manager(filesystem).ensure_ignored(project_root: root)
    rescue GitIgnoreError => error
      assert(error.message.include?(File.join(root, '.gitignore')),
             'replacement diagnostic omitted the path')
    else
      raise('FAIL: concurrent replacement was accepted')
    end
    assert(filesystem.open_calls == 1, 'replacement was retried')
    assert(snapshot(root) == baseline, 'replacement changed Git state')
  end

  def verify_symlink_before_open
    root, path = fixture('symlink before open')
    victim = File.join(root, 'unrelated.txt')
    File.binwrite(victim, "do not change this file\n")
    filesystem = GitIgnoreReplacementFilesystem.new(
      filesystem: File,
      before_open: lambda do |target|
        File.rename(target, "#{target}.original")
        File.symlink(victim, target)
      end
    )
    rejected(root, filesystem)
    assert(File.binread(victim) == "do not change this file\n",
           'symlink target was modified')
    assert(File.binread("#{path}.original") == "existing-rule\n",
           'original ignore file was modified')
    assert(File.symlink?(path), 'replacement symlink was removed')
  end

  def replace_with_regular_file(path)
    replacement = "#{path}.replacement"
    File.binwrite(replacement, "replacement-rule\n")
    File.rename(path, "#{path}.original")
    File.rename(replacement, path)
  end

  def verify_symlink_after_open
    root, path = fixture('symlink after open')
    victim = File.join(root, 'unrelated.txt')
    File.binwrite(victim, "do not change this file\n")
    filesystem = GitIgnoreReplacementFilesystem.new(
      filesystem: File,
      after_open: lambda do |target|
        File.rename(target, "#{target}.original")
        File.symlink(victim, target)
      end
    )
    rejected(root, filesystem)
    assert(File.binread(victim) == "do not change this file\n",
           'late symlink target was modified')
    assert(File.binread("#{path}.original") == "existing-rule\n",
           'detached original was written after symlink replacement')
  end

  def verify_regular_file_before_open
    root, path = fixture('regular replacement before open')
    filesystem = GitIgnoreReplacementFilesystem.new(
      filesystem: File, before_open: method(:replace_with_regular_file)
    )
    rejected(root, filesystem)
    assert(File.binread(path) == "replacement-rule\n",
           'replacement regular file was modified')
    assert(File.binread("#{path}.original") == "existing-rule\n",
           'original regular file was modified')
  end

  def verify_regular_file_after_open
    root, path = fixture('regular replacement after open')
    filesystem = GitIgnoreReplacementFilesystem.new(
      filesystem: File, after_open: method(:replace_with_regular_file)
    )
    rejected(root, filesystem)
    assert(File.binread(path) == "replacement-rule\n",
           'replacement after opening was modified')
    assert(File.binread("#{path}.original") == "existing-rule\n",
           'detached original was written after replacement')
  end

  def verify_concurrent_creation
    root, path = fixture('concurrent creation', contents: nil)
    filesystem = GitIgnoreReplacementFilesystem.new(
      filesystem: File,
      before_open: ->(target) { File.binwrite(target, "another creator\n") }
    )
    rejected(root, filesystem)
    assert(File.binread(path) == "another creator\n",
           'concurrently created file was overwritten')
  end

  def verify_missing_file_creation
    root, path = fixture('missing ignore file', contents: nil)
    baseline = snapshot(root)
    assert(manager(File).ensure_ignored(project_root: root),
           'missing ignore file was not prepared')
    assert(File.binread(path) == "/wr/\n", 'wrong new ignore rule')
    checker = GitIgnoreChecker.new(command_runner: self)
    assert(checker.ignored?(project_root: root),
           'Git does not ignore storage after creation')
    assert(snapshot(root) == baseline, 'ignore creation changed Git state')
  end

  def verify_real_git_exclusion
    original = "/wr/\n!/wr/"
    root, path = fixture('cancelled ignore rule', contents: original)
    checker = GitIgnoreChecker.new(command_runner: self)
    assert(!checker.ignored?(project_root: root),
           'fixture negation did not cancel exclusion')
    baseline = snapshot(root)
    filesystem = GitIgnoreReplacementFilesystem.new(filesystem: File)
    prepared = manager(filesystem)
    assert(prepared.ensure_ignored(project_root: root),
           'ignore repair failed')
    assert(File.binread(path) == "#{original}\n/wr/\n",
           'existing ignore contents were not preserved')
    Dir.mkdir(File.join(root, 'wr'))
    File.binwrite(File.join(root, 'wr/Record.json'), '{}')
    assert(checker.ignored?(project_root: root), 'Git still includes storage')
    assert(git(root, 'check-ignore', '--', 'wr/Record.json').strip ==
           'wr/Record.json', 'Git does not ignore storage contents')
    unchanged = [File.binread(path), File.stat(path).mtime]
    assert(prepared.ensure_ignored(project_root: root), 'repeat setup failed')
    assert(filesystem.open_calls == 1, 'already ignored file was opened again')
    assert([File.binread(path), File.stat(path).mtime] == unchanged,
           'already ignored file was rewritten')
    assert(snapshot(root) == baseline, 'ignore repair changed Git state')
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    GitIgnoreManagerIntegrationTest.new(
      workspace_root: OrchTestPaths::WORKSPACE_ROOT,
      command_runner: Open3
    ).run
  rescue StandardError => error
    warn("Git-ignore integration tests failed: " \
         "#{error.class}: #{error.message}")
    exit(1)
  end
end
