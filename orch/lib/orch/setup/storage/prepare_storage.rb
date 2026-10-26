require 'open3'

require_relative 'storage_preparation_error'
require_relative 'storage_root_resolver'
require_relative 'storage_directory_creator'
require_relative 'storage_preparation'
require_relative '../git/git_ignore_error'
require_relative '../git/git_ignore_checker'
require_relative '../git/git_ignore_manager'

class StoragePreparationEntryPoint
  def initialize(preparation:, output:, errors:)
    @preparation = preparation
    @output = output
    @errors = errors
  end

  def run(arguments:)
    unless arguments.length == 1
      @errors.puts('Usage: prepare_storage.rb PROJECT_ROOT')
      return 2
    end

    storage_root = @preparation.run(
      project_root: arguments.fetch(0)
    )

    @output.puts(storage_root)
    0
  rescue StoragePreparationError, GitIgnoreError,
         SystemCallError, IOError => error
    @errors.puts("#{error.class}: #{error.message}")
    1
  end
end

if $PROGRAM_NAME == __FILE__
  ignore_checker = GitIgnoreChecker.new(
    command_runner: Open3
  )

  ignore_manager = GitIgnoreManager.new(
    filesystem: File,
    ignore_checker: ignore_checker
  )

  directory_creator = StorageDirectoryCreator.new(
    filesystem: File,
    directory_writer: Dir
  )

  preparation = StoragePreparation.new(
    root_resolver: StorageRootResolver,
    git_ignore_manager: ignore_manager,
    directory_creator: directory_creator
  )

  entry_point = StoragePreparationEntryPoint.new(
    preparation: preparation,
    output: $stdout,
    errors: $stderr
  )

  exit(entry_point.run(arguments: ARGV))
end
