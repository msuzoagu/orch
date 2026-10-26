# frozen_string_literal: true

# Shared test startup: provide project paths and enable library imports.
# Locate the plugin relative to this helper, not individual test files or
# the caller's working directory. Tests use OrchTestPaths for shared roots.
# Start tests with -I <plugin-root>/tests so require 'test_helper' finds us.
# Globals: Defines OrchTestPaths constants and adds LIBRARY_ROOT to this
#   process's $LOAD_PATH unless present. Does not change ENV or run tests.
# Arguments: None.
# Outputs: None.

# Absolute, immutable paths for the source plugin and its workspace.
# Use these constants to locate shared files and workspace fixtures;
# individual tests do not need to know their directory depth.
module OrchTestPaths
  # The orch directory containing this helper's tests directory.
  PLUGIN_ROOT = File.expand_path('..', __dir__).freeze

  # The enclosing workspace, where tests keep disposable fixtures.
  WORKSPACE_ROOT = File.dirname(PLUGIN_ROOT).freeze

  # Production Ruby files, loaded by names such as orch/setup/git/....
  LIBRARY_ROOT = File.join(PLUGIN_ROOT, 'lib').freeze
end

$LOAD_PATH.unshift(OrchTestPaths::LIBRARY_ROOT) unless
  $LOAD_PATH.include?(OrchTestPaths::LIBRARY_ROOT)
