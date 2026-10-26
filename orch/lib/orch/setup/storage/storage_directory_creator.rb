# frozen_string_literal: true

require_relative 'storage_preparation_error'

class StorageDirectoryCreator
  def initialize(filesystem:, directory_writer:)
    @filesystem = filesystem
    @directory_writer = directory_writer
  end

  def ensure_exists(storage_root:)
    validate(storage_root:)
    return storage_root if @filesystem.exist?(storage_root)

    begin
      @directory_writer.mkdir(storage_root)
    rescue Errno::EEXIST
      # Another caller may have created it; validate, never replace it.
      validate(storage_root:)
    end

    validate(storage_root:)
    unless @filesystem.directory?(storage_root)
      raise(
        StoragePreparationError,
        "Create storage at #{storage_root}: directory does not exist"
      )
    end

    storage_root
  rescue SystemCallError, IOError => error
    raise(
      StoragePreparationError,
      "Create storage at #{storage_root}: #{error.class}: #{error.message}"
    )
  end

  def validate(storage_root:)
    unless storage_root.is_a?(String) &&
           storage_root.start_with?('/')
      raise(
        StoragePreparationError,
        'Storage root must be an absolute directory path'
      )
    end

    if @filesystem.symlink?(storage_root)
      raise(
        StoragePreparationError,
        "Storage root must not be a symbolic link: #{storage_root}"
      )
    end

    target = if @filesystem.exist?(storage_root)
               storage_root
             else
               @filesystem.dirname(storage_root)
             end

    unless @filesystem.stat(target).directory?
      raise(
        StoragePreparationError,
        "Storage target is not a directory: #{target}"
      )
    end

    unless @filesystem.writable?(target)
      raise(
        StoragePreparationError,
        "Storage target is not writable: #{target}"
      )
    end

    true
  rescue SystemCallError, IOError => error
    raise(
      StoragePreparationError,
      "Validate storage at #{storage_root}: " \
      "#{error.class}: #{error.message}"
    )
  end
end
