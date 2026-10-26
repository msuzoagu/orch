@rem  Bundled Ruby launcher for native Windows Command Prompt.
@rem
@rem  Usage:
@rem    ruby_launcher.cmd [Ruby options] [Ruby script] [script args]
@rem    Quote arguments containing spaces according to cmd.exe rules.
@rem    All arguments belong to Ruby; this launcher has no private options.
@rem
@rem  Startup contract:
@rem    Find the installed plugin from this launcher's directory.
@rem    Select runtime-configs/Windows-<architecture>.cmd.
@rem    Prefer PROCESSOR_ARCHITEW6432 over PROCESSOR_ARCHITECTURE.
@rem    Load the selected trusted configuration's four required values:
@rem      ORCH_RUNTIME_CONFIG_VERSION must be 1.
@rem      ORCH_RUNTIME_DIR is relative to the installed plugin directory.
@rem      ORCH_RUBY_EXECUTABLE is relative to the runtime directory.
@rem      ORCH_GEM_DIR is relative to the runtime directory.
@rem    Configurations contain literal assignments and comments only.
@rem    Paths use backslashes, with no leading separator, colon, or '..'
@rem    component. The Ruby executable must be a native .exe file.
@rem    Set bundled gem paths and clear inherited Ruby/Bundler settings.
@rem    Run Ruby with the original arguments, working directory, and I/O.
@rem    Startup checks fail with a STDERR message and exit status 78.
@rem    After Ruby runs, return its exit status unchanged.
@rem    Environment changes are local to this launcher and its child.
@rem
@rem  Deferred tests and the Windows CALL path-handling concern:
@rem    See architecture/in-review/DeferredWork.md at the repository root,
@rem    sections "Linux and Windows Launcher Tests" and
@rem    "Windows CALL Path Handling".
@rem
@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "orch_script_dir=%~dp0"

rem Defer the path expansion until CALL's second parsing pass.
call :orch_locate_plugin "%%orch_script_dir%%.."
if errorlevel 1 exit /b 78

call :orch_select_configuration
if errorlevel 1 exit /b 78

call :orch_load_configuration
if errorlevel 1 exit /b 78

call :orch_resolve_paths
if errorlevel 1 exit /b 78

call :orch_check_runtime
if errorlevel 1 exit /b 78

call :orch_prepare_ruby_environment
if errorlevel 1 exit /b 78

rem  Invoke the native executable directly; preserve the original args.
rem  No command may alter the exit status between Ruby and this return.
rem  With no explicit code, EXIT /B retains Ruby's current exit status.
"%orch_ruby_executable%" %*
exit /b

rem #####################################################################
rem  Resolve the installed plugin directory and verify both directories.
rem  Leave the caller's working directory unchanged.
rem  Globals:
rem    orch_script_dir (read): Absolute launcher directory, ending in '\'.
rem    orch_plugin_dir (set): Absolute installed plugin directory.
rem    orch_error (set on failure): Message consumed by orch_fail.
rem  Arguments:
rem    %1 - Plugin directory path; main passes the launcher's parent.
rem    Defer variable expansion in CALL as shown in the main sequence.
rem  Returns:
rem    0 on success; 78 on a directory-resolution failure.
rem  Outputs:
rem    Writes an error to STDERR on failure; no output on success.
rem #####################################################################
:orch_locate_plugin
set "orch_plugin_dir=%~f1"

if not exist "%orch_script_dir%." (
  set "orch_error=cannot resolve launcher directory: %orch_script_dir%"
  goto :orch_fail
)
if not defined orch_plugin_dir (
  set "orch_error=cannot determine the plugin directory"
  goto :orch_fail
)
if not exist "%orch_plugin_dir%\." (
  set "orch_error=cannot resolve plugin directory: %orch_plugin_dir%"
  goto :orch_fail
)
exit /b 0

rem #####################################################################
rem  Select one Windows configuration using the native architecture.
rem  Require a configuration file rather than a directory.
rem  Globals:
rem    PROCESSOR_ARCHITECTURE (read): Command interpreter architecture.
rem    PROCESSOR_ARCHITEW6432 (read): Native architecture when present.
rem    orch_script_dir (read): Absolute launcher directory, ending in '\'.
rem    orch_arch (set): Selected processor architecture identifier.
rem    orch_platform (set): Windows-<architecture> identifier.
rem    orch_config (set): Absolute path to the selected configuration.
rem    orch_error (set on failure): Message consumed by orch_fail.
rem  Arguments:
rem    None
rem  Returns:
rem    0 on success; 78 if architecture or configuration is unavailable.
rem  Outputs:
rem    Writes an error to STDERR on failure; no output on success.
rem #####################################################################
:orch_select_configuration
set "orch_arch=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "orch_arch=%PROCESSOR_ARCHITEW6432%"

if not defined orch_arch (
  set "orch_error=cannot identify the processor architecture"
  goto :orch_fail
)
set "orch_platform=Windows-%orch_arch%"
set "orch_config=%orch_script_dir%runtime-configs\%orch_platform%.cmd"

if not exist "%orch_config%" (
  set "orch_error=configuration not found for %orch_platform%: %orch_config%"
  goto :orch_fail
)
if exist "%orch_config%\." (
  set "orch_error=configuration path is a directory: %orch_config%"
  goto :orch_fail
)
exit /b 0

rem ####################################################################
rem  Clear inherited configuration values and load the selected file.
rem  The trusted file must contain only literal assignments and comments.
rem  Require format version 1 and all three nonempty path values.
rem  Globals:
rem    orch_config (read): Path selected by orch_select_configuration.
rem    ORCH_RUNTIME_CONFIG_VERSION (cleared, loaded, and validated).
rem    ORCH_RUNTIME_DIR (cleared, loaded, and validated).
rem    ORCH_RUBY_EXECUTABLE (cleared, loaded, and validated).
rem    ORCH_GEM_DIR (cleared, loaded, and validated).
rem    orch_error (set on failure): Message consumed by orch_fail.
rem  Arguments:
rem    None
rem  Returns:
rem    0 on success; 78 if loading or required-value checks fail.
rem  Outputs:
rem    Writes an error to STDERR on failure; no output on success.
rem ####################################################################
:orch_load_configuration
set "ORCH_RUNTIME_CONFIG_VERSION="
set "ORCH_RUNTIME_DIR="
set "ORCH_RUBY_EXECUTABLE="
set "ORCH_GEM_DIR="

rem Expand the filename only during CALL's second parsing pass.
call "%%orch_config%%"
if errorlevel 1 (
  set "orch_error=cannot load configuration: %orch_config%"
  goto :orch_fail
)
if not "%ORCH_RUNTIME_CONFIG_VERSION%"=="1" (
  set "orch_error=configuration version must be 1: %orch_config%"
  goto :orch_fail
)
if not defined ORCH_RUNTIME_DIR (
  set "orch_error=ORCH_RUNTIME_DIR is missing: %orch_config%"
  goto :orch_fail
)
if not defined ORCH_RUBY_EXECUTABLE (
  set "orch_error=ORCH_RUBY_EXECUTABLE is missing: %orch_config%"
  goto :orch_fail
)
if not defined ORCH_GEM_DIR (
  set "orch_error=ORCH_GEM_DIR is missing: %orch_config%"
  goto :orch_fail
)
exit /b 0

rem ########################################################################
rem  Validate a nonempty relative Windows path supplied through globals.
rem  Reject leading separators, colons, forward slashes, and '..' components.
rem  Use variables so a path is not reparsed as a CALL argument.
rem  Globals:
rem    orch_config (read): Configuration path included in diagnostics.
rem    orch_path_name (read): Configuration variable being checked.
rem    orch_path (read): Literal path to validate, using backslashes.
rem    orch_path_components (set): Path with surrounding separators.
rem    orch_error (set): Failure message; only emitted on failure.
rem  Arguments:
rem    None; set orch_path_name and orch_path before calling.
rem  Returns:
rem    0 on success; 78 on an empty or invalid relative path.
rem  Outputs:
rem    Writes an error to STDERR on failure; no output on success.
rem ########################################################################
:orch_check_relative_path
set "orch_error=invalid relative path for %orch_path_name% in %orch_config%: %orch_path%"
if not defined orch_path goto :orch_fail
if "%orch_path:~0,1%"=="\" goto :orch_fail
if not "%orch_path::=%"=="%orch_path%" goto :orch_fail
if not "%orch_path:/=%"=="%orch_path%" goto :orch_fail

set "orch_path_components=\%orch_path%\"
if not "%orch_path_components:\..\=%"=="%orch_path_components%" goto :orch_fail
exit /b 0

rem ####################################################################
rem  Validate loaded paths and derive absolute runtime paths.
rem  Resolve the runtime against the plugin directory, then Ruby and gems
rem  against the runtime. Derive the cache path without creating it.
rem  Globals:
rem    orch_plugin_dir (read): Absolute installed plugin directory.
rem    orch_config (read for path-validation error messages).
rem    ORCH_RUNTIME_DIR (read): Runtime path relative to the plugin.
rem    ORCH_RUBY_EXECUTABLE (read): Ruby path relative to the runtime.
rem    ORCH_GEM_DIR (read): Gem path relative to the runtime.
rem    orch_path_name, orch_path (set): Inputs to path validation.
rem    orch_path_components, orch_error (set by path validation).
rem    orch_runtime_dir (set): Absolute runtime directory.
rem    orch_ruby_executable (set): Absolute Ruby executable path.
rem    orch_gem_dir (set): Absolute gem directory.
rem    orch_gem_spec_cache (set): The gem directory's spec_cache child.
rem  Arguments:
rem    None
rem  Returns:
rem    0 on success; 78 on an invalid configured path.
rem  Outputs:
rem    Writes an error to STDERR on failure; no output on success.
rem ####################################################################
:orch_resolve_paths
set "orch_path_name=ORCH_RUNTIME_DIR"
set "orch_path=%ORCH_RUNTIME_DIR%"
call :orch_check_relative_path
if errorlevel 1 exit /b 78

set "orch_path_name=ORCH_RUBY_EXECUTABLE"
set "orch_path=%ORCH_RUBY_EXECUTABLE%"
call :orch_check_relative_path
if errorlevel 1 exit /b 78

set "orch_path_name=ORCH_GEM_DIR"
set "orch_path=%ORCH_GEM_DIR%"
call :orch_check_relative_path
if errorlevel 1 exit /b 78

set "orch_runtime_dir=%orch_plugin_dir%\%ORCH_RUNTIME_DIR%"
set "orch_ruby_executable=%orch_runtime_dir%\%ORCH_RUBY_EXECUTABLE%"
set "orch_gem_dir=%orch_runtime_dir%\%ORCH_GEM_DIR%"
set "orch_gem_spec_cache=%orch_gem_dir%\spec_cache"
exit /b 0

rem ####################################################################
rem  Require existing runtime and gem directories and a Ruby .exe file.
rem  Reject a directory in place of the executable.
rem  Call after orch_resolve_paths; this does not execute Ruby.
rem  Globals:
rem    orch_runtime_dir (read): Absolute runtime directory.
rem    orch_ruby_executable (read): Absolute Ruby executable path.
rem    orch_gem_dir (read): Absolute gem directory.
rem    orch_error (set on failure): Message consumed by orch_fail.
rem  Arguments:
rem    None
rem  Returns:
rem    0 on success; 78 if a required directory or executable is invalid.
rem  Outputs:
rem    Writes an error to STDERR on failure; no output on success.
rem ####################################################################
:orch_check_runtime
if not exist "%orch_runtime_dir%\." (
  set "orch_error=runtime directory not found: %orch_runtime_dir%"
  goto :orch_fail
)
if /i not "%orch_ruby_executable:~-4%"==".exe" (
  set "orch_error=Ruby executable must be an .exe file: %orch_ruby_executable%"
  goto :orch_fail
)
if not exist "%orch_ruby_executable%" (
  set "orch_error=Ruby executable not found: %orch_ruby_executable%"
  goto :orch_fail
)
if exist "%orch_ruby_executable%\." (
  set "orch_error=Ruby executable path is a directory: %orch_ruby_executable%"
  goto :orch_fail
)
if not exist "%orch_gem_dir%\." (
  set "orch_error=gem directory not found: %orch_gem_dir%"
  goto :orch_fail
)
exit /b 0

rem #####################################################################
rem  Set configured gem paths and clear the inherited Ruby and Bundler
rem  settings cleared by the Unix launcher. Call after orch_check_runtime.
rem  Changes apply to Ruby's child environment within the SETLOCAL scope.
rem  Set the cache path without creating its directory.
rem  Globals:
rem    orch_gem_dir (read): Resolved gem directory.
rem    orch_gem_spec_cache (read): Resolved gem cache path.
rem    GEM_HOME, GEM_PATH, GEM_SPEC_CACHE (set for the Ruby child).
rem    RUBYOPT, RUBYLIB, RUBYGEMS_GEMDEPS (unset).
rem    BUNDLER_SETUP, BUNDLE_BIN_PATH, BUNDLE_GEMFILE (unset).
rem    BUNDLE_PATH, BUNDLE_APP_CONFIG (unset).
rem  Arguments:
rem    None
rem  Returns:
rem    0 on success.
rem  Outputs:
rem    None
rem #####################################################################
:orch_prepare_ruby_environment
set "RUBYOPT="
set "RUBYLIB="
set "RUBYGEMS_GEMDEPS="
set "BUNDLER_SETUP="
set "BUNDLE_BIN_PATH="
set "BUNDLE_GEMFILE="
set "BUNDLE_PATH="
set "BUNDLE_APP_CONFIG="

set "GEM_HOME=%orch_gem_dir%"
set "GEM_PATH=%orch_gem_dir%"
set "GEM_SPEC_CACHE=%orch_gem_spec_cache%"
exit /b 0

rem ###################################################################
rem  Report a startup failure and return to the calling startup step.
rem  The caller must propagate status 78 to stop the launcher.
rem  GOTO this label within a subroutine to return from that subroutine.
rem  Globals:
rem    orch_error (read): Startup failure message.
rem  Arguments:
rem    None; set orch_error before transferring control here.
rem  Returns:
rem    78; the main sequence propagates it to the launcher's caller.
rem  Outputs:
rem    Writes the message with an 'orch:' prefix to STDERR.
rem  Outstanding Windows execution checks are recorded in
rem  architecture/in-review/DeferredWork.md at the repository root.
rem ###################################################################
:orch_fail
>&2 echo orch: "%orch_error%"
exit /b 78
