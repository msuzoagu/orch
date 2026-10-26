# frozen_string_literal: true

# Own the database location shared by preparation and key allocation.
module WrKeyDatabasePath
  ######################################################################
  # Construct the shared WorkRequest key allocation database path.
  # The caller supplies the storage path already resolved by Setup.
  # Globals:
  #   None.
  # Arguments:
  #   storage_root: Absolute WorkRequest storage path resolved by Setup.
  # Outputs:
  #   None.
  # Returns:
  #   String containing <storage-root>/.system/wr-keys.sqlite3.
  ######################################################################
  def self.resolve(storage_root:)
    File.join(storage_root, '.system', 'wr-keys.sqlite3')
  end
end

