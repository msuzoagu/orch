# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'

class StoragePreparationIntegrationTest
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
    @launcher = File.join(
      workspace_root, 'orch/scripts/ruby_launcher.sh'
    )
  end

  def run
    parent = File.join(@workspace_root, '.unclassified')
    FileUtils.mkdir_p(parent)
    Dir.mktmpdir('storage-workflow-', parent) do |fixture_root|
      @fixture_root = fixture_root
      @environment['GIT_CEILING_DIRECTORIES'] = File.realpath(fixture_root)
      verify_new_storage
      verify_existing_contents_and_repeat_calls
      verify_untracking_then_preparation
      verify_invalid_storage
      verify_invalid_ignore_file
      verify_unwritable_storage
      verify_non_repository
      verify_invalid_arguments
    end
    puts('PASS: complete storage-preparation command with real Git')
  end

  private

  def assert(condition, message)
    raise("FAIL: #{message}") unless condition
  end

  def capture(*command, chdir: @workspace_root)
    result = @command_runner.capture3(@environment, *command, chdir:)
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

  def fixture(name)
    root = File.join(@fixture_root, name)
    Dir.mkdir(root)
    git(root, 'init', '--quiet', '--template=')
    File.binwrite(File.join(root, 'project.txt'), "preserve project\n")
    git(root, 'add', '--', 'project.txt')
    git(root, '-c', 'commit.gpgsign=false', 'commit', '--quiet',
        '-m', 'Create disposable preparation fixture')
    root
  end

  def command(entry_point, *arguments, chdir: @workspace_root)
    entry_path = File.join(
      @workspace_root, 'orch/lib/orch/setup/storage', entry_point
    )
    capture('/bin/sh', @launcher, entry_path, *arguments, chdir:)
  end

  def snapshot(root)
    [
      File.binread(File.join(root, '.git/index')),
      git(root, 'rev-parse', 'HEAD'),
      git(root, 'symbolic-ref', 'HEAD')
    ]
  end

  def tracking(root)
    output, diagnostic, status = command(
      'manage_storage_tracking.rb', 'check', root
    )
    assert(status.exitstatus == 0 && diagnostic.empty?,
           'real tracking check failed')
    JSON.parse(output)
  end

  def prepare(root, chdir: @workspace_root)
    output, diagnostic, status = command('prepare_storage.rb', root, chdir:)
    assert(status.exitstatus == 0 && diagnostic.empty?,
           "preparation failed: #{diagnostic}")
    assert(output == "#{File.join(root, 'wr')}\n",
           'preparation returned the wrong storage path')
  end

  def verify_ready(root)
    storage = File.join(root, 'wr')
    assert(File.directory?(storage) && !File.symlink?(storage),
           'storage is missing or is a symbolic link')
    assert(File.writable?(storage), 'prepared storage is not writable')
    assert(git(root, 'check-ignore', '--', 'wr/').strip == 'wr/',
           'Git does not effectively ignore storage')
    assert(tracking(root).empty?, 'prepared storage remains tracked')
  end

  def verify_new_storage
    root = fixture('new project with spaces')
    nested = File.join(root, 'nested')
    Dir.mkdir(nested)
    discovered = git(nested, 'rev-parse', '--show-toplevel').strip
    assert(File.realpath(discovered) == File.realpath(root),
           'subdirectory discovery returned the wrong project root')
    baseline = snapshot(root)
    prepare(discovered, chdir: nested)
    verify_ready(discovered)
    assert(File.binread(File.join(root, '.gitignore')) == "/wr/\n",
           'missing ignore file was not created correctly')
    assert(Dir.children(File.join(root, 'wr')).empty?,
           'preparation created WorkRequest files')
    assert(snapshot(root) == baseline, 'preparation changed Git state')
  end

  def verify_existing_contents_and_repeat_calls
    root = fixture('existing storage and dirty project')
    storage = File.join(root, 'wr')
    Dir.mkdir(storage)
    record = File.join(storage, 'existing Record.json')
    File.binwrite(record, '{"preserve":true}')
    ignore = File.join(root, '.gitignore')
    original = "/wr/\n!/wr/"
    File.binwrite(ignore, original)
    File.binwrite(
      File.join(root, 'project.txt'), "uncommitted project change\n"
    )
    baseline = snapshot(root)
    prepare(root)
    verify_ready(root)
    assert(File.binread(ignore) == "#{original}\n/wr/\n",
           'existing ignore rules were overwritten')
    assert(git(root, 'check-ignore', '--', 'wr/existing Record.json').strip ==
           'wr/existing Record.json', 'existing stored file is not ignored')
    unchanged = [File.binread(ignore), File.stat(ignore).mtime,
                 File.stat(storage).mtime, File.binread(record)]
    prepare(root)
    verify_ready(root)
    assert([File.binread(ignore), File.stat(ignore).mtime,
            File.stat(storage).mtime, File.binread(record)] == unchanged,
           'repeat preparation changed existing storage or ignore rules')
    assert(File.binread(record) == '{"preserve":true}', 'Record was changed')
    assert(File.binread(File.join(root, 'project.txt')) ==
           "uncommitted project change\n", 'unrelated project change was lost')
    assert(snapshot(root) == baseline, 'preparation staged or committed files')
  end

  def verify_untracking_then_preparation
    root = fixture('tracked storage then preparation')
    Dir.mkdir(File.join(root, 'wr'))
    record = File.join(root, 'wr/Record.json')
    File.binwrite(record, '{"preserve":true}')
    git(root, 'add', '--', 'wr/')
    git(root, '-c', 'commit.gpgsign=false', 'commit', '--quiet',
        '-m', 'Track fixture storage before setup')
    baseline = snapshot(root)
    assert(tracking(root) == ['wr/Record.json'], 'tracked storage was missed')
    output, diagnostic, status = command(
      'manage_storage_tracking.rb', 'untrack', root, '--approved'
    )
    assert(status.exitstatus == 0 && diagnostic.empty? &&
           JSON.parse(output) == [],
           'approved untracking failed before preparation')
    after_untracking = snapshot(root)
    prepare(root)
    verify_ready(root)
    assert(File.binread(record) == '{"preserve":true}',
           'untracking or preparation removed the local Record')
    assert(snapshot(root) == after_untracking,
           'preparation changed the approved untracking result')
    staged = git(root, 'diff', '--cached', '--name-only').strip
    assert(staged == 'wr/Record.json',
           'unexpected files were staged')
    assert(after_untracking.drop(1) == baseline.drop(1),
           'setup committed or changed branches')
  end

  def reject_preparation(root, message)
    baseline = snapshot(root)
    output, diagnostic, status = command('prepare_storage.rb', root)
    assert(status.exitstatus == 1 && output.empty?,
           'invalid preparation returned success or a storage path')
    assert(diagnostic.include?(message), 'failure diagnostic was lost')
    assert(snapshot(root) == baseline, 'failed preparation changed Git state')
  end

  def verify_invalid_storage
    ['file', 'symlink', 'dangling link'].each do |kind|
      root = fixture("invalid storage #{kind}")
      storage = File.join(root, 'wr')
      if kind == 'file'
        File.binwrite(storage, 'preserve invalid target')
      else
        destination = kind == 'symlink' ? root : File.join(root, 'missing')
        File.symlink(destination, storage)
      end
      diagnostic = kind == 'file' ? 'not a directory' : 'symbolic link'
      reject_preparation(root, diagnostic)
      assert(!File.exist?(File.join(root, '.gitignore')),
             'invalid storage caused an ignore-file write')
      if kind == 'file'
        assert(File.binread(storage) == 'preserve invalid target',
               'invalid storage file was overwritten')
      else
        assert(File.symlink?(storage), 'invalid storage link was removed')
      end
    end
  end

  def verify_invalid_ignore_file
    root = fixture('symlink ignore file')
    victim = File.join(root, 'unrelated.txt')
    File.binwrite(victim, 'preserve unrelated file')
    File.symlink(victim, File.join(root, '.gitignore'))
    reject_preparation(root, 'symbolic link')
    assert(File.binread(victim) == 'preserve unrelated file',
           'invalid ignore file changed its symlink target')
    assert(!File.exist?(File.join(root, 'wr')),
           'ignore-file failure did not stop directory creation')
  end

  def verify_unwritable_storage
    root = fixture('unwritable storage')
    storage = File.join(root, 'wr')
    Dir.mkdir(storage)
    begin
      File.chmod(0o555, storage)
      assert(!File.writable?(storage), 'fixture is not actually unwritable')
      reject_preparation(root, 'not writable')
      assert(!File.exist?(File.join(root, '.gitignore')),
             'unwritable storage caused an ignore-file write')
    ensure
      File.chmod(0o755, storage)
    end
  end

  def verify_non_repository
    root = File.join(@fixture_root, 'not a repository')
    Dir.mkdir(root)
    output, diagnostic, status = command('prepare_storage.rb', root)
    assert(status.exitstatus == 1 && output.empty?,
           'non-repository preparation was accepted')
    assert(diagnostic.include?('Check ignore rules'),
           'non-repository diagnostic was lost')
    assert(Dir.children(root).empty?, 'non-repository failure wrote files')
  end

  def verify_invalid_arguments
    root = fixture('invalid arguments')
    baseline = snapshot(root)
    output, diagnostic, status = command('prepare_storage.rb')
    assert(status.exitstatus == 2 && output.empty? &&
           diagnostic.include?('Usage:'),
           'missing arguments did not produce a usage error')
    output, diagnostic, status = command(
      'prepare_storage.rb', 'relative/project'
    )
    assert(status.exitstatus == 1 && output.empty? &&
           diagnostic.include?('absolute'), 'relative root was accepted')
    assert(snapshot(root) == baseline, 'invalid arguments changed Git state')
    assert(!File.exist?(File.join(root, 'wr')),
           'invalid arguments created storage')
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    StoragePreparationIntegrationTest.new(
      workspace_root: OrchTestPaths::WORKSPACE_ROOT,
      command_runner: Open3
    ).run
  rescue StandardError => error
    warn("Preparation integration tests failed: " \
         "#{error.class}: #{error.message}")
    exit(1)
  end
end
