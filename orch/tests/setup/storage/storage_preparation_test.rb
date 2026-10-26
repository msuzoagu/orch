# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'orch/setup/storage/prepare_storage'

class StorageDirectoryWriterDouble
  attr_reader :calls

  def initialize(before_create: nil, error: nil, no_creation: false)
    @before_create = before_create
    @error = error
    @no_creation = no_creation
    @calls = []
  end

  def mkdir(path)
    @calls << path
    @before_create.call(path) if @before_create
    raise(@error) if @error
    return if @no_creation

    Dir.mkdir(path)
  end
end

class StorageIgnoreCheckerDouble
  attr_reader :calls

  def initialize(results:)
    @results = results.dup
    @calls = []
  end

  def ignored?(project_root:)
    @calls << File.directory?(File.join(project_root, 'wr'))
    result = @results.shift
    raise(result) if result.is_a?(Exception)
    raise('Unexpected ignore-check call') if result.nil?

    result
  end
end

class StoragePreparationOutputDouble
  attr_reader :lines

  def initialize
    @lines = []
  end

  def puts(value)
    @lines << value
  end
end

class StoragePreparationTest
  def initialize
    @checks = 0
    @workspace_root = OrchTestPaths::WORKSPACE_ROOT
  end

  def run
    fixture_root = File.join(@workspace_root, '.unclassified')
    FileUtils.mkdir_p(fixture_root)
    Dir.mktmpdir('storage-preparation-', fixture_root) do |fixture|
      @fixture = fixture
      verify_existing_storage_readiness
      verify_creation_and_preservation
      verify_invalid_targets
      verify_creation_races
      verify_creation_failures
      verify_coordinator
      verify_entry_point
    end
    puts("PASS: #{@checks} storage-preparation assertions")
  end

  private

  def assert(condition, message)
    raise("FAIL: #{message}") unless condition

    @checks += 1
  end

  def assert_error(message, error_class: StoragePreparationError)
    yield
  rescue error_class => error
    assert(error.message.include?(message), 'failure diagnostic was lost')
  else
    raise('FAIL: expected failure was accepted')
  end

  def project(name)
    path = File.join(@fixture, name)
    Dir.mkdir(path)
    path
  end

  def creator(writer = Dir)
    StorageDirectoryCreator.new(filesystem: File, directory_writer: writer)
  end

  def preparation(checker:, writer: Dir)
    StoragePreparation.new(
      root_resolver: StorageRootResolver,
      git_ignore_manager: GitIgnoreManager.new(
        filesystem: File, ignore_checker: checker
      ),
      directory_creator: creator(writer)
    )
  end

  def verify_existing_storage_readiness
    skill = File.read(
      File.join(OrchTestPaths::PLUGIN_ROOT, 'skills/setup/SKILL.md')
    )
    readiness = skill.split('## Check Setup Readiness', 2).last
      .split('## Obtain Setup Authorization', 2).first
    command = readiness.scan(/```sh\n(.*?)\n\s*```/m)
      .flatten.find { |block| block.include?('test -w') }
    assert(!command.nil?, 'readiness skips existing storage writability')
    assert(readiness.index('test -w') < readiness.index('git -C'),
           'writability is checked after the ready-path Git check')
    assert(readiness.include?('Do not change permissions or continue intake.'),
           'unwritable storage does not explicitly stop intake')

    target = project('existing ignored storage')
    root = File.join(target, 'wr')
    ignore = File.join(target, '.gitignore')
    Dir.mkdir(root)
    File.write(ignore, "/wr/\n")
    record = File.join(root, 'Record.json')
    File.write(record, 'preserve existing work')
    original_mode = File.stat(root).mode & 0o777
    command = command.gsub('<project-root>', '${1}')

    begin
      File.chmod(0o755, root)
      output, diagnostic, status = Open3.capture3(
        '/bin/sh', '-c', command, 'setup-readiness', target
      )
      assert(status.exitstatus == 0, 'writable storage failed readiness')
      assert(output.empty? && diagnostic.empty?, 'readiness check wrote output')

      File.chmod(0o555, root)
      output, diagnostic, status = Open3.capture3(
        '/bin/sh', '-c', command, 'setup-readiness', target
      )
      assert(status.exitstatus == 1, 'unwritable storage passed readiness')
      assert(output.empty? && diagnostic.empty?, 'check attempted a write')
    ensure
      File.chmod(original_mode, root)
    end

    assert(File.read(ignore) == "/wr/\n", 'readiness changed Git exclusion')
    assert(File.read(record) == 'preserve existing work', 'Record was changed')
    assert(Dir.children(root) == ['Record.json'], 'readiness created files')
  end

  def verify_creation_and_preservation
    root = File.join(project('directory with spaces'), 'wr')
    writer = StorageDirectoryWriterDouble.new
    directory_creator = creator(writer)
    assert(directory_creator.ensure_exists(storage_root: root) == root,
           'creation did not return the storage path')
    assert(File.directory?(root), 'storage directory was not created')
    record = File.join(root, 'existing Record.json')
    File.write(record, 'preserve this record')
    assert(directory_creator.ensure_exists(storage_root: root) == root,
           'repeat preparation failed')
    assert(writer.calls == [root], 'existing directory was recreated')
    assert(File.read(record) == 'preserve this record', 'Record was changed')
  end

  def verify_invalid_targets
    parent = project('invalid targets')
    file = File.join(parent, 'file')
    File.write(file, 'preserve this file')
    link = File.join(parent, 'link')
    File.symlink(parent, link)
    dangling = File.join(parent, 'dangling')
    File.symlink(File.join(parent, 'missing'), dangling)
    writer = StorageDirectoryWriterDouble.new
    directory_creator = creator(writer)
    [nil, '', 'relative/wr'].each do |path|
      assert_error('absolute directory path') do
        directory_creator.ensure_exists(storage_root: path)
      end
    end
    [link, dangling].each do |path|
      assert_error('symbolic link') do
        directory_creator.ensure_exists(storage_root: path)
      end
    end
    assert_error('not a directory') do
      directory_creator.ensure_exists(storage_root: file)
    end
    assert_error('Validate storage') do
      directory_creator.ensure_exists(
        storage_root: File.join(parent, 'missing parent', 'wr')
      )
    end
    assert(writer.calls.empty?, 'invalid target triggered directory creation')
    assert(File.read(file) == 'preserve this file', 'file was overwritten')
  end

  def verify_creation_races
    parent = project('creation races')
    directory = File.join(parent, 'directory')
    writer = StorageDirectoryWriterDouble.new(
      before_create: ->(path) { Dir.mkdir(path) }
    )
    assert(creator(writer).ensure_exists(storage_root: directory) == directory,
           'concurrently created directory was rejected')
    assert(writer.calls == [directory], 'creation was retried')
    file = File.join(parent, 'file')
    writer = StorageDirectoryWriterDouble.new(
      before_create: ->(path) { File.write(path, 'preserve concurrent file') }
    )
    assert_error('not a directory') do
      creator(writer).ensure_exists(storage_root: file)
    end
    assert(File.read(file) == 'preserve concurrent file', 'race file replaced')
    link = File.join(parent, 'link')
    writer = StorageDirectoryWriterDouble.new(
      before_create: ->(path) { File.symlink(parent, path) }
    )
    assert_error('symbolic link') do
      creator(writer).ensure_exists(storage_root: link)
    end
  end

  def verify_creation_failures
    root = File.join(project('creation failures'), 'wr')
    writer = StorageDirectoryWriterDouble.new(
      error: IOError.new('simulated directory-write failure')
    )
    assert_error("Create storage at #{root}: IOError") do
      creator(writer).ensure_exists(storage_root: root)
    end
    assert(writer.calls == [root], 'failed creation was retried')
    assert(!File.exist?(root), 'failed creation reported a directory')
    assert_error('directory does not exist') do
      creator(StorageDirectoryWriterDouble.new(no_creation: true))
        .ensure_exists(storage_root: root)
    end
  end

  def verify_coordinator
    target = project('complete preparation')
    ignore = File.join(target, '.gitignore')
    File.write(ignore, 'existing-rule')
    checker = StorageIgnoreCheckerDouble.new(results: [false, true, true])
    coordinator = preparation(checker:)
    root = File.join(target, 'wr')
    assert(coordinator.run(project_root: target) == root, 'wrong result path')
    assert(File.directory?(root), 'coordinator did not create storage')
    assert(checker.calls == [false, false], 'creation preceded Git exclusion')
    expected = "existing-rule\n/wr/\n"
    assert(File.read(ignore) == expected, 'existing ignore contents changed')
    assert(coordinator.run(project_root: target) == root, 'repeat setup failed')
    assert(File.read(ignore) == expected, 'repeat setup duplicated ignore rule')

    target = project('new ignore file')
    checker = StorageIgnoreCheckerDouble.new(results: [false, true])
    preparation(checker:).run(project_root: target)
    assert(File.read(File.join(target, '.gitignore')) == "/wr/\n",
           'missing ignore file was not created')

    target = project('preflight failure')
    root = File.join(target, 'wr')
    File.write(root, 'not a directory')
    checker = StorageIgnoreCheckerDouble.new(results: [])
    assert_error('not a directory') do
      preparation(checker:).run(project_root: target)
    end
    assert(!File.exist?(File.join(target, '.gitignore')),
           'invalid storage target changed ignore rules')

    target = project('ignore failure')
    checker = StorageIgnoreCheckerDouble.new(
      results: [GitIgnoreError.new('simulated ignore failure')]
    )
    assert_error('simulated ignore failure', error_class: GitIgnoreError) do
      preparation(checker:).run(project_root: target)
    end
    assert(Dir.children(target).empty?, 'ignore failure did not stop writes')

    target = project('partial preparation')
    checker = StorageIgnoreCheckerDouble.new(results: [false, true])
    writer = StorageDirectoryWriterDouble.new(
      error: IOError.new('write failed')
    )
    assert_error('write failed') do
      preparation(checker:, writer:).run(project_root: target)
    end
    assert(File.read(File.join(target, '.gitignore')) == "/wr/\n",
           'completed ignore change was silently reverted')
    assert(!File.exist?(File.join(target, 'wr')), 'failed creation continued')
  end

  def verify_entry_point
    target = project('entry point')
    checker = StorageIgnoreCheckerDouble.new(results: [true])
    output = StoragePreparationOutputDouble.new
    errors = StoragePreparationOutputDouble.new
    entry = StoragePreparationEntryPoint.new(
      preparation: preparation(checker:), output:, errors:
    )
    assert(entry.run(arguments: [target]) == 0, 'entry point reported failure')
    assert(output.lines == [File.join(target, 'wr')], 'wrong stdout result')
    assert(errors.lines.empty?, 'success emitted a diagnostic')

    target = project('entry failure')
    checker = StorageIgnoreCheckerDouble.new(results: [true])
    writer = StorageDirectoryWriterDouble.new(
      error: IOError.new('write failed')
    )
    output = StoragePreparationOutputDouble.new
    errors = StoragePreparationOutputDouble.new
    entry = StoragePreparationEntryPoint.new(
      preparation: preparation(checker:, writer:), output:, errors:
    )
    assert(entry.run(arguments: [target]) == 1, 'failure returned success')
    assert(output.lines.empty?, 'failed setup printed a storage path')
    assert(errors.lines.fetch(0).include?('write failed'), 'diagnostic missing')
    assert(entry.run(arguments: []) == 2, 'invalid arguments accepted')
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    StoragePreparationTest.new.run
  rescue StandardError => error
    warn("Storage preparation tests failed: #{error.class}: #{error.message}")
    exit(1)
  end
end
