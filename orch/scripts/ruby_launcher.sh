#!/bin/sh
set -eu

########################################################
# Report a startup failure and terminate the launcher.
# Globals:
#   None
# Arguments:
#   $1 - Error message.
# Outputs:
#   Writes the message with an 'orch:' prefix to STDERR.
# Returns:
#   Does not return; exits the launcher with status 78.
########################################################
orch_fail() {
    printf 'orch: %s\n' "$*" >&2
    exit 78
}

orch_invoked_dir=$(/usr/bin/dirname "$0") || {
    orch_fail 'cannot determine launcher directory:' "$0"
}

orch_script_dir=$(
  CDPATH= cd -- "$orch_invoked_dir" && pwd -P
) || {
    orch_fail 'cannot resolve launcher directory:' "$orch_invoked_dir"
}

orch_plugin_dir=$(
  CDPATH= cd -- "$orch_script_dir/.." && pwd -P
) || {
    orch_fail 'cannot resolve plugin directory:' "$orch_script_dir/.."
}


#######################################################################
# Reject absolute prefixes, drive prefixes, and '..' path components.
# Required-value checks must establish that the path is nonempty first.
# Globals:
#   orch_config (read for error messages).
# Arguments:
#   $1 - Configuration variable name, used in error messages.
#   $2 - Nonempty configured Unix path, using '/' separators.
# Outputs:
#   Writes an error to STDERR on failure; no output on success.
# Returns:
#   0 on success; exits the launcher with status 78 on an invalid path.
#######################################################################
orch_check_relative_path() {
    case "$2" in
    /*|\\*|[A-Za-z]:*)
        orch_fail "$1 must be relative in $orch_config: $2"
        ;;
    esac

    case "/$2/" in
    */../*)
        orch_fail "$1 contains a '..' component in $orch_config: $2"
        ;;
    esac
}

########################################################################
# Select runtime-configs/<OS>-<architecture>.sh using uname identifiers.
# Require the selected configuration to be a readable regular file.
# Globals:
#   orch_script_dir (read): Absolute launcher directory.
#   orch_uname_cmd (set and read): Selected absolute path to uname.
#   orch_os (set): Operating-system identifier from uname -s.
#   orch_arch (set): Processor architecture identifier from uname -m.
#   orch_platform (set): Combined OS and architecture identifier.
#   orch_config (set): Absolute path to the selected configuration.
# Arguments:
#   None
# Outputs:
#   Writes an error to STDERR on failure; no output on success.
# Returns:
#   0 on success; exits the launcher with status 78 on failure.
########################################################################
orch_select_configuration() {

    # 1. Locate the binary safely across Linux and macOS
    if [ -x /usr/bin/uname ]; then
    orch_uname_cmd="/usr/bin/uname"
    elif [ -x /bin/uname ]; then
    orch_uname_cmd="/bin/uname"
    else
    orch_fail "uname command utility not found in standard system paths"
    fi

    # 2. Read operating-system and processor architecture identifiers
    orch_os=$("$orch_uname_cmd" -s) ||
    orch_fail "cannot identify the operating system"
    orch_arch=$("$orch_uname_cmd" -m) ||
    orch_fail "cannot identify the processor architecture"

    # 3. Validate presence
    [ -n "$orch_os" ] ||
    orch_fail "operating-system identifier is empty"
    [ -n "$orch_arch" ] ||
    orch_fail "processor architecture identifier is empty"

    # 4. Construct platform config path
    orch_platform="$orch_os-$orch_arch"
    orch_config="$orch_script_dir/runtime-configs/$orch_platform.sh"

    # 5.  File system checks
    [ -f "$orch_config" ] ||
    orch_fail "configuration not found for $orch_platform: $orch_config"
    [ -r "$orch_config" ] ||
    orch_fail "configuration is unreadable: $orch_config"
}

######################################################################
# Clear inherited configuration values and load the selected file.
# The trusted file must contain only literal assignments and comments.
# Check shell syntax, format version 1, and nonempty required values.
# Globals:
#   orch_config (read): Path selected by orch_select_configuration.
#   ORCH_RUNTIME_CONFIG_VERSION (cleared, loaded, and validated).
#   ORCH_RUNTIME_DIR (cleared, loaded, and validated).
#   ORCH_RUBY_EXECUTABLE (cleared, loaded, and validated).
#   ORCH_GEM_DIR (cleared, loaded, and validated).
# Arguments:
#   None
# Outputs:
#   Writes an error to STDERR on failure; no output on success.
# Returns:
#   0 on success; exits the launcher with status 78 on failure.
######################################################################
orch_load_configuration() {
    ORCH_RUNTIME_CONFIG_VERSION=''
    ORCH_RUNTIME_DIR=''
    ORCH_RUBY_EXECUTABLE=''
    ORCH_GEM_DIR=''

    /bin/sh -n "$orch_config" >/dev/null 2>&1 ||
    orch_fail "invalid shell syntax in configuration: $orch_config"

    . "$orch_config" ||
    orch_fail "cannot load configuration: $orch_config"

    [ "$ORCH_RUNTIME_CONFIG_VERSION" = '1' ] ||
    orch_fail "configuration version must be 1: $orch_config"
    [ -n "$ORCH_RUNTIME_DIR" ] ||
    orch_fail "ORCH_RUNTIME_DIR is missing: $orch_config"
    [ -n "$ORCH_RUBY_EXECUTABLE" ] ||
    orch_fail "ORCH_RUBY_EXECUTABLE is missing: $orch_config"
    [ -n "$ORCH_GEM_DIR" ] ||
    orch_fail "ORCH_GEM_DIR is missing: $orch_config"
}

#######################################################################
# Validate loaded relative paths and derive absolute runtime paths.
# Resolve the runtime against the plugin directory, then Ruby and gems
# against the runtime. Derive the cache path without creating it.
# Globals:
#   orch_plugin_dir (read): Absolute installed plugin directory.
#   orch_config (read for path-validation error messages).
#   ORCH_RUNTIME_DIR (read): Runtime path relative to the plugin.
#   ORCH_RUBY_EXECUTABLE (read): Ruby path relative to the runtime.
#   ORCH_GEM_DIR (read): Gem path relative to the runtime.
#   orch_runtime_dir (set): Absolute runtime directory.
#   orch_ruby_executable (set): Absolute Ruby executable path.
#   orch_gem_dir (set): Absolute gem directory.
#   orch_gem_spec_cache (set): The gem directory's spec_cache child.
# Arguments:
#   None
# Outputs:
#   Writes an error to STDERR on failure; no output on success.
# Returns:
#   0 on success; exits the launcher with status 78 on an invalid path.
#######################################################################
orch_resolve_paths() {
    orch_check_relative_path ORCH_RUNTIME_DIR "$ORCH_RUNTIME_DIR"
    orch_check_relative_path ORCH_RUBY_EXECUTABLE "$ORCH_RUBY_EXECUTABLE"
    orch_check_relative_path ORCH_GEM_DIR "$ORCH_GEM_DIR"

    orch_runtime_dir="$orch_plugin_dir/$ORCH_RUNTIME_DIR"
    orch_ruby_executable="$orch_runtime_dir/$ORCH_RUBY_EXECUTABLE"
    orch_gem_dir="$orch_runtime_dir/$ORCH_GEM_DIR"
    orch_gem_spec_cache="$orch_gem_dir/spec_cache"
}

######################################################################
# Require existing runtime and gem directories and a regular Ruby file
# with executable permission. Call after orch_resolve_paths.
# Globals:
#   orch_runtime_dir (read): Absolute runtime directory.
#   orch_ruby_executable (read): Absolute Ruby executable path.
#   orch_gem_dir (read): Absolute gem directory.
# Arguments:
#   None
# Outputs:
#   Writes an error to STDERR on failure; no output on success.
# Returns:
#   0 on success; exits the launcher with status 78 on failure.
######################################################################
orch_check_runtime() {
    [ -d "$orch_runtime_dir" ] ||
    orch_fail "runtime directory not found: $orch_runtime_dir"
    [ -f "$orch_ruby_executable" ] ||
    orch_fail "Ruby executable not found: $orch_ruby_executable"
    [ -x "$orch_ruby_executable" ] ||
    orch_fail "Ruby file is not executable: $orch_ruby_executable"
    [ -d "$orch_gem_dir" ] ||
    orch_fail "gem directory not found: $orch_gem_dir"
}

######################################################################
# Export configured gem paths and clear the inherited Ruby and Bundler
# settings cleared by the v0 launcher. Call after orch_check_runtime.
# Export the cache path without creating its directory.
# Globals:
#   orch_gem_dir (read): Resolved gem directory.
#   orch_gem_spec_cache (read): Resolved gem cache path.
#   GEM_HOME, GEM_PATH, GEM_SPEC_CACHE (set and exported).
#   RUBYOPT, RUBYLIB, RUBYGEMS_GEMDEPS (unset).
#   BUNDLER_SETUP, BUNDLE_BIN_PATH, BUNDLE_GEMFILE (unset).
#   BUNDLE_PATH, BUNDLE_APP_CONFIG (unset).
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 on success.
######################################################################
orch_prepare_ruby_environment() {
    unset RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS \
    BUNDLER_SETUP BUNDLE_BIN_PATH BUNDLE_GEMFILE \
    BUNDLE_PATH BUNDLE_APP_CONFIG

    GEM_HOME="$orch_gem_dir"
    GEM_PATH="$orch_gem_dir"
    GEM_SPEC_CACHE="$orch_gem_spec_cache"
    export GEM_HOME GEM_PATH GEM_SPEC_CACHE
}

orch_select_configuration
orch_load_configuration
orch_resolve_paths
orch_check_runtime
orch_prepare_ruby_environment

# 6. Replace the launcher with Ruby, preserving arguments and I/O.
exec "$orch_ruby_executable" "$@"
