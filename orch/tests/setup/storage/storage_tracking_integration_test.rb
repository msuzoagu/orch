# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

class StorageTrackingIntegrationTest
  def initialize(workspace_root:, command_runner:)
    @workspace_root = workspace_root
    @command_runner = command_runner
    @checks = 0
    @environment = {
      'GIT_CONFIG_GLOBAL' => '/dev/null',
      'GIT_CONFIG_NOSYSTEM' => '1',
      'GIT_AUTHOR_NAME' => 'Orch Integration Test',
      'GIT_AUTHOR_EMAIL' => 'orch-test@example.invalid',
      'GIT_COMMITTER_NAME' => 'Orch Integration Test',
      'GIT_COMMITTER_EMAIL' => 'orch-test@example.invalid'
    }
    @launcher = File.join(
      workspace_root, 'orch/scripts/ruby_launcher.sh'
    )
    @entry_point = File.join(
      workspace_root, 'orch/lib/orch/setup/storage/manage_storage_tracking.rb'
    )
  end

  def run
    fixture_parent = File.join(@workspace_root, '.unclassified')
    FileUtils.mkdir_p(fixture_parent)
    Dir.mktmpdir('real-git-storage-', fixture_parent) do |fixture_root|
      @fixture_root = fixture_root
      verify_detection_and_approval_refusal
      verify_approved_untracking
      verify_already_untracked_storage
      verify_missing_storage
      verify_staged_content_conflict
      verify_index_lock
    end
    puts("PASS: #{@checks} real-Git storage-tracking assertions")
  end

  private

  def assert(condition, message)
    raise("FAIL: #{message}") unless condition

    @checks += 1
  end

  def capture(*command)
    result = @command_runner.capture3(@environment, *command)
    if result.fetch(1).match?(/Operation not permitted|Permission denied/i)
      raise("Permission block running #{command.inspect}: #{result.fetch(1)}")
    end

    result
  rescue SystemCallError, IOError => error
    raise("Command #{command.inspect}: #{error.class}: #{error.message}")
  end

  def git(root, *arguments)
    output, diagnostic, status = capture('git', '-C', root, *arguments)
    unless status.success?
      raise("Fixture Git #{arguments.inspect} in #{root}: #{diagnostic}")
    end

    output
  end

  def fixture(name, tracked: true)
    root = File.join(@fixture_root, name)
    Dir.mkdir(root)
    git(root, 'init', '--quiet', '--template=')
    FileUtils.mkdir_p(File.join(root, 'wr/nested'))
    files = {
      '.gitignore' => "/wr/\n",
      'project.txt' => "unrelated project file\n",
      'wr/Record.json' => "{\"fixture\":true}\n",
      "wr/nested/file with spaces\nand newline.md" => "preserve findings\n"
    }
    files.each do |path, contents|
      File.binwrite(File.join(root, path), contents)
    end
    git(root, 'add', '--', '.gitignore', 'project.txt')
    git(root, 'add', '-f', '--', 'wr/') if tracked
    git(root, '-c', 'commit.gpgsign=false', 'commit', '--quiet',
        '-m', 'Create disposable integration fixture')
    [root, files]
  end

  def helper(operation, root, approved: false)
    arguments = [operation, root]
    arguments << '--approved' if approved
    capture('/bin/sh', @launcher, @entry_point, *arguments)
  end

  def paths_in_index(root)
    git(root, 'ls-files', '-z', '--', 'wr/').split("\0")
  end

  def snapshot(root)
    {
      index: File.binread(File.join(root, '.git/index')),
      head: git(root, 'rev-parse', 'HEAD'),
      branch: git(root, 'symbolic-ref', 'HEAD')
    }
  end

  def verify_files(root, files)
    files.each do |path, contents|
      assert(File.binread(File.join(root, path)) == contents,
             "Local file was removed or changed: #{path.inspect}")
    end
  end

  def verify_detection_and_approval_refusal
    root, files = fixture('ignored tracked storage with spaces')
    baseline = snapshot(root)
    ignored = git(root, 'check-ignore', '--no-index', '--', 'wr/')
    assert(ignored.strip == 'wr/', 'fixture ignore rule does not match storage')

    output, diagnostic, status = helper('check', root)
    expected = files.keys.select { |path| path.start_with?('wr/') }.sort
    assert(status.exitstatus == 0 && diagnostic.empty?, 'real check failed')
    assert(JSON.parse(output).sort == expected,
           'ignored tracked files or unusual filenames were missed')
    assert(snapshot(root) == baseline, 'read-only check changed Git state')

    output, diagnostic, status = helper('untrack', root)
    assert(status.exitstatus == 1 && output.empty?,
           'unapproved untracking returned success')
    assert(diagnostic.include?('Untracking requires Human approval'),
           'unapproved untracking omitted its diagnostic')
    assert(snapshot(root) == baseline, 'missing approval changed Git state')
    assert(paths_in_index(root).sort == expected,
           'unapproved files were untracked')
    verify_files(root, files)
  end

  def verify_approved_untracking
    root, files = fixture('approved untracking')
    files['project.txt'] = "unrelated staged change\n"
    File.binwrite(File.join(root, 'project.txt'), files.fetch('project.txt'))
    git(root, 'add', '--', 'project.txt')
    baseline = snapshot(root)
    unrelated_staged = git(root, 'show', ':project.txt')

    output, diagnostic, status = helper('untrack', root, approved: true)
    assert(status.exitstatus == 0 && diagnostic.empty?,
           'real untracking failed')
    assert(JSON.parse(output) == [], 'untracking did not verify empty tracking')
    assert(paths_in_index(root).empty?,
           'storage remains in the real Git index')
    staged_removals = git(
      root, 'diff', '--cached', '--name-only', '--diff-filter=D',
      '-z', '--', 'wr/'
    ).split("\0").sort
    expected = files.keys.select { |path| path.start_with?('wr/') }.sort
    assert(staged_removals == expected, 'storage removals were not staged')
    assert(git(root, 'show', ':project.txt') == unrelated_staged,
           'untracking changed unrelated staged contents')
    assert(git(root, 'ls-files', '-z', '--', '.gitignore', 'project.txt')
           .split("\0").sort == ['.gitignore', 'project.txt'],
           'untracking changed unrelated file tracking')
    assert(git(root, 'rev-parse', 'HEAD') == baseline.fetch(:head),
           'untracking created a commit')
    assert(git(root, 'symbolic-ref', 'HEAD') == baseline.fetch(:branch),
           'untracking changed branches')
    verify_files(root, files)

    after_untracking = snapshot(root)
    output, diagnostic, status = helper('untrack', root, approved: true)
    assert(status.exitstatus == 0 && JSON.parse(output) == [] &&
           diagnostic.empty?,
           'repeated untracking failed')
    assert(snapshot(root) == after_untracking,
           'repeated untracking changed state')
    output, diagnostic, status = helper('check', root)
    assert(status.exitstatus == 0 && JSON.parse(output) == [] &&
           diagnostic.empty?,
           'follow-up check still reports tracked storage')
  end

  def verify_already_untracked_storage
    root, files = fixture('already untracked', tracked: false)
    baseline = snapshot(root)
    output, diagnostic, status = helper('untrack', root, approved: true)
    assert(status.exitstatus == 0 && JSON.parse(output) == [] &&
           diagnostic.empty?,
           'already untracked storage was rejected')
    assert(snapshot(root) == baseline,
           'already untracked storage changed state')
    verify_files(root, files)
  end

  def verify_missing_storage
    root, files = fixture('missing storage with tracked paths')
    # Remove only this generated fixture's storage, keeping its Git index.
    FileUtils.remove_entry(File.join(root, 'wr'))
    baseline = snapshot(root)
    output, diagnostic, status = helper('check', root)
    expected = files.keys.select { |path| path.start_with?('wr/') }.sort
    assert(status.exitstatus == 0 && JSON.parse(output).sort == expected,
           'missing storage hid tracked index entries')
    assert(diagnostic.empty?, 'missing storage emitted an unexpected error')
    assert(snapshot(root) == baseline,
           'missing-storage check changed Git state')
    output, diagnostic, status = helper('untrack', root, approved: true)
    assert(status.exitstatus == 0 && JSON.parse(output) == [] &&
           diagnostic.empty?,
           'missing-storage entries could not be untracked')
    assert(paths_in_index(root).empty?,
           'missing-storage entries remain tracked')
    assert(!File.exist?(File.join(root, 'wr')), 'untracking created storage')
  end

  def verify_staged_content_conflict
    root, files = fixture('staged content conflict')
    record = File.join(root, 'wr/Record.json')
    File.binwrite(record, "staged second version\n")
    git(root, 'add', '-f', '--', 'wr/Record.json')
    files['wr/Record.json'] = "unstaged third version\n"
    File.binwrite(record, files.fetch('wr/Record.json'))
    baseline = snapshot(root)

    output, diagnostic, status = helper('untrack', root, approved: true)
    assert(status.exitstatus == 1 && output.empty?,
           'conflicting staged contents were forcibly untracked')
    assert(diagnostic.include?('Git rm') && diagnostic.include?('staged'),
           'staged-content conflict diagnostic was lost')
    assert(snapshot(root) == baseline, 'conflict changed the index or history')
    assert(git(root, 'show', ':wr/Record.json') == "staged second version\n",
           'conflict discarded staged contents')
    verify_files(root, files)
  end

  def verify_index_lock
    root, files = fixture('locked index')
    lock = File.join(root, '.git/index.lock')
    File.binwrite(lock, 'test-owned index lock')
    baseline = snapshot(root)
    output, diagnostic, status = helper('untrack', root, approved: true)
    assert(status.exitstatus == 1 && output.empty?,
           'locked index reported successful untracking')
    assert(diagnostic.include?('index.lock'), 'index-lock diagnostic was lost')
    assert(File.binread(lock) == 'test-owned index lock',
           'index lock was removed')
    assert(snapshot(root) == baseline, 'locked index changed Git state')
    verify_files(root, files)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    StorageTrackingIntegrationTest.new(
      workspace_root: OrchTestPaths::WORKSPACE_ROOT,
      command_runner: Open3
    ).run
  rescue StandardError => error
    warn("Real-Git integration tests failed: #{error.class}: #{error.message}")
    exit(1)
  end
end
