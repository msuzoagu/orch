# AGENTS.md

## 0. Security & Permissions

- **Workspace:** Stay strictly within the local project workspace.

- **File Verification:** Verify edits using local, path-isolated
  readers such as `nl -ba <file>` or `cat <file>`.

- **Repo Tracking:** Use `git status` or `git diff` only to review
  overall repository state.

- **Permission Blocks:** On any OS security block, permission error
  (including "Operation not permitted"), or unreadable configuration,
  stop all task work immediately. Report the command or tool, affected
  path or configuration, exact error, and any known cause to the user.
  Do not retry, troubleshoot system paths, change visibility rules,
  or modify system environment settings to bypass the block.
  Any required Full Disk Access or TCC permissions must be granted
  manually by the user.

## 1. Explicit Rules

- **Grounded Accuracy:** Never overstate confidence. If a response is
  not grounded in verifiable repository facts, explicitly label it as
  a hypothesis, estimation, or creative output. Use qualifiers when
  data is incomplete.

- **Clear Communication:** Use the specific tool or feature name
  instead of a generic description—for example, “Codex CLI version”
  instead of "target installed client version." Explain necessary
  technical terms in plain language for junior developers and
  non-technical product owners.

## 2. Runtime and Dependency Isolation

- **Environment Isolation:** Never modify or depend on host
  operating system's global runtime environments; always use
  project-specific, isolated runtimes and user-space dependencies.

## 3. Scripting Language Policy

- **High-Level Scripting:** Every high-level, dynamically typed
  interpreted script must be written exclusively in Ruby.

- **Low-Level Automation:** For system automation, use POSIX
  shell scripts (`.sh`) on macOS and Linux, and Windows command scripts
  (`.cmd`) on Windows. Native Windows support must not require Bash,
  Git Bash, or WSL.

- **Platform Compatibility:** Keep platform-specific startup commands
  in separate Unix and Windows launchers with the same launch contract.
  Keep shared higher-level logic in Ruby.

- **Decision Rule:** If a task requires complex logic, loops, data
  structures, or API calls, use Ruby. If a task simply runs sequential
  system commands, use the appropriate Unix shell or Windows command
  script described above.

## 4. Code Style Guidelines

- **Max Line Length:** Strictly enforce an 72-character maximum column
  width for all Markdown files (.md).

- **Line Wrapping:** Use hard wrapping for prose text, but disable
  line length limits for Markdown tables and code blocks.
