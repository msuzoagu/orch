# frozen_string_literal: true

class StoragePreparation
  def initialize(
    root_resolver:,
    git_ignore_manager:,
    directory_creator:
  )
    @root_resolver = root_resolver
    @git_ignore_manager = git_ignore_manager
    @directory_creator = directory_creator
  end

  def run(project_root:)
    storage_root = @root_resolver.resolve(project_root:)

    @git_ignore_manager.validate(project_root:)
    @directory_creator.validate(storage_root:)

    @git_ignore_manager.ensure_ignored(project_root:)
    @directory_creator.ensure_exists(storage_root:)

    storage_root
  end
end
