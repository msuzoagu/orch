# frozen_string_literal: true

# Establishes exclusion, without knowing Git exit codes.
class GitIgnoreManager
  def initialize(filesystem:, ignore_checker:)
    @filesystem = filesystem
    @ignore_checker = ignore_checker
  end

  def ensure_ignored(project_root:)
    validate(project_root:)
    return true if @ignore_checker.ignored?(project_root:)

    path = File.join(project_root, '.gitignore')
    append_ignore_rule(path:)
    verify_after_write(project_root:, path:)

    true
  end

  def validate(project_root:)
    unless project_root.is_a?(String) &&
           project_root.start_with?('/') &&
           @filesystem.directory?(project_root)
      raise(
        GitIgnoreError,
        'Validate project root: expected an existing absolute directory'
      )
    end

    path = File.join(project_root, '.gitignore')

    if @filesystem.symlink?(path)
      raise(GitIgnoreError, "Validate #{path}: symbolic link not permitted")
    end

    return true unless @filesystem.exist?(path)

    unless @filesystem.file?(path) && @filesystem.readable?(path)
      raise(GitIgnoreError, "Validate #{path}: expected readable regular file")
    end

    true
  rescue SystemCallError => error
    raise(
      GitIgnoreError,
      "Validate #{project_root}: #{error.class}: #{error.message}"
    )
  end

  private

  def append_ignore_rule(path:)
    expected = ignore_file_stat(path:)
    if expected && !expected.file?
      raise(GitIgnoreError, "Write #{path}: expected a regular file")
    end

    flags = protected_open_flags(existing: expected)
    @filesystem.open(path, flags, 0o666) do |file|
      file.binmode
      verify_open_file(path:, file:, expected:)
      contents = file.read
      verify_open_file(path:, file:, expected:)

      prefix = contents.empty? || contents.end_with?("\n") ? '' : "\n"
      file.write("#{prefix}/wr/\n")
      file.flush
      verify_open_file(path:, file:, expected:)
    end
  rescue SystemCallError, IOError => error
    raise(
      GitIgnoreError,
      "Write #{path}: #{error.class}: #{error.message}; " \
      'the write may have partially completed'
    )
  end

  def ignore_file_stat(path:)
    @filesystem.lstat(path)
  rescue Errno::ENOENT
    nil
  end

  def protected_open_flags(existing:)
    unless File.const_defined?(:NOFOLLOW)
      raise(GitIgnoreError, 'Safe Git-ignore opening requires File::NOFOLLOW')
    end

    # Reject links atomically; do not block if replaced with a FIFO.
    flags = File::RDWR | File::APPEND | File::NOFOLLOW | File::NONBLOCK
    flags |= File::CREAT | File::EXCL unless existing
    flags
  end

  def verify_open_file(path:, file:, expected:)
    opened = file.stat
    current = @filesystem.lstat(path)
    unless opened.file? && current.file? && same_file?(opened, current) &&
           (expected.nil? || same_file?(opened, expected))
      raise(
        GitIgnoreError,
        "Write #{path}: file was replaced or is not a regular file; " \
        'stop without retrying or reverting changes'
      )
    end
  end

  def same_file?(first, second)
    first.dev == second.dev && first.ino == second.ino
  end

  def verify_after_write(project_root:, path:)
    return if @ignore_checker.ignored?(project_root:)

    raise(GitIgnoreError, 'Git still does not ignore wr/')
  rescue GitIgnoreError => error
    raise(
      GitIgnoreError,
      "Verify exclusion after changing #{path}: #{error.message}; " \
      'the file change has not been reverted'
    )
  end
end
