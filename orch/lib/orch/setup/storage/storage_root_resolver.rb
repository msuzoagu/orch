require_relative 'storage_preparation_error'

module StorageRootResolver
  def self.resolve(project_root:, filesystem: File)
    unless project_root.is_a?(String) &&
           project_root.start_with?('/')
      raise(
        StoragePreparationError,
        'Project root must be an absolute directory path'
      )
    end

    unless filesystem.stat(project_root).directory?
      raise(
        StoragePreparationError,
        "Project root is not a directory: #{project_root}"
      )
    end

    filesystem.join(
      filesystem.expand_path(project_root),
      'wr'
    )
  rescue SystemCallError, IOError => error
    raise(
      StoragePreparationError,
      "Resolve storage under #{project_root}: " \
      "#{error.class}: #{error.message}"
    )
  end
end
