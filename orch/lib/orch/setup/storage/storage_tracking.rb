# frozen_string_literal: true

require_relative 'storage_preparation_error'

class StorageTracking
  def initialize(command_runner:)
    @command_runner = command_runner
  end

  def tracked_paths(project_root:)
    output = execute(
      project_root:, arguments: ['ls-files', '-z', '--', 'wr/']
    )
    paths = output.split("\0")
    unless paths.all? { |path| path.start_with?('wr/') || path == 'wr' }
      raise(StoragePreparationError, 'Git returned paths outside wr/')
    end

    paths
  end

  def untrack(project_root:, authorized:)
    unless authorized == true
      raise(StoragePreparationError, 'Untracking requires Human approval')
    end
    return [] if tracked_paths(project_root:).empty?

    execute(project_root:, arguments: ['rm', '-r', '--cached', '--', 'wr/'])
    remaining = tracked_paths(project_root:)
    unless remaining.empty?
      raise(
        StoragePreparationError,
        "Git still tracks storage paths: #{remaining.inspect}"
      )
    end

    remaining
  end

  private

  def execute(project_root:, arguments:)
    unless project_root.is_a?(String) && project_root.start_with?('/')
      raise(StoragePreparationError, 'Project root must be an absolute path')
    end

    output, diagnostic, status = @command_runner.capture3(
      { 'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1' },
      'git', '-C', project_root, *arguments
    )
    unless status.exitstatus == 0
      raise(
        StoragePreparationError,
        "Git #{arguments.first} in #{project_root} failed " \
        "(exit #{status.exitstatus.inspect}): #{diagnostic.strip}"
      )
    end

    output
  rescue SystemCallError, IOError => error
    raise(
      StoragePreparationError,
      "Git #{arguments.first} in #{project_root}: " \
      "#{error.class}: #{error.message}"
    )
  end
end
