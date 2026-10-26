# Local Tests

Tests use the existing dependency-free assertion harness and bundled
Ruby. No new gems are required.

Run the commands below from the repository root. Each command supplies
`-I orch/tests` so Ruby can find `test_helper.rb`. Every test loads this
helper, which adds the absolute `orch/lib` directory to Ruby's library
search path (`$LOAD_PATH`) for that process. Tests then use `require`
with library names such as `orch/setup/git/git_ignore_checker`.

The helper also provides absolute paths through `OrchTestPaths`.
`PLUGIN_ROOT` identifies `orch/`; `WORKSPACE_ROOT` identifies its
enclosing workspace; `LIBRARY_ROOT` identifies `orch/lib/`. Tests use
these constants to locate project files and keep fixtures inside the
workspace, without calculating paths from their own directory depth.

From another working directory, use absolute paths for the launcher,
the `-I` tests directory, and the test file. The helper locates the
library relative to itself and does not change the working directory,
environment variables, or the global Ruby installation.

Tests are grouped by component. Unit and integration tests for the same
component share a directory:

```text
tests/
├── README.md
├── test_helper.rb
├── hooks/
│   └── question_setup_hook_test.rb
├── runtime/
│   └── runtime_delivery_test.rb
└── setup/
    ├── git/
    │   ├── git_ignore_checker_test.rb
    │   └── git_ignore_manager_integration_test.rb
    └── storage/
        ├── storage_preparation_test.rb
        ├── storage_preparation_integration_test.rb
        ├── storage_tracking_test.rb
        └── storage_tracking_integration_test.rb
```

## Storage Preparation

```sh
sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/setup/storage/storage_preparation_test.rb
```

Checks directory creation, preservation, invalid targets, creation
collisions, failures, coordination order, and entry-point results.
Runs Setup's read-only writability command against writable and
unwritable existing directories and checks the stop instruction.
Temporary filesystem fixtures stay inside the workspace and are removed
after each run. Git results are simulated; this test does not execute
Git or establish installed-client behavior.

## Complete Storage Preparation with Real Git

```sh
sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/setup/storage/storage_preparation_integration_test.rb
```

Runs the Bundled Ruby Launcher and preparation entry point as
subprocesses against disposable workspace repositories. Checks discovery
from a subdirectory, new storage, effective exclusion, preservation,
repeat runs, and approved untracking followed by preparation. Invalid
targets, unwritable storage, non-repositories, and invalid arguments
must fail without reporting readiness. Git index, commits, branches, and
unrelated project changes are checked for preservation.

These calls exercise the commands used after approval. They do not
simulate or verify a Human's authorization conversation. Fixture commits
use test-only identity and exclude global/system Git configuration.
Fixtures are removed afterward; permission blocks stop the test.
Git discovery stops at the fixture boundary, not the enclosing project.

## Installed-Agent Approval and Resume: Not Yet Verified

An installed-client test must invoke the actual Question skill, inspect
the authorization prompt, and verify files and the Git index while no
answer has been supplied. Separate cases must supply No, an unclear
answer, and Yes, then check stopping, waiting, or approved preparation.
After Yes, the same invocation must retain the exact Question and resume
intake without resubmission. Already-ready projects bypass approval.
Tracked storage needs its separate untracking approval.

This requires a live agent-client test driver and access to the
installed plugin. Reading skill text or running helpers does not prove
behavior. No such conversation test has been executed by these suites.

## Git Configuration Isolation

```sh
sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/setup/git/git_ignore_checker_test.rb
```

Checks command arguments, per-command configuration isolation, and
failure reporting with an injected command double. It does not execute
Git or read global configuration.

## Question Setup Hook

```sh
sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/hooks/question_setup_hook_test.rb
```

For scope and the installed-client test, see
[the hook instructions](../hooks/README.md).

## Git-Ignore Replacement and Effective Exclusion

```sh
sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/setup/git/git_ignore_manager_integration_test.rb
```

Uses disposable workspace repositories and real Git. An injected
filesystem collaborator replaces `.gitignore` at the exact opening
boundary, avoiding timing-dependent tests. Checks symlink and regular
file replacement, concurrent creation, preservation, missing-file
creation, and repeat calls without writes. Git checks confirm that
appending `/wr/` overrides a prior negation and excludes stored files.
Fixture-only commits use test identity and exclude global/system Git
configuration. Fixtures are removed afterward; no real project index
or installed plugin is changed. Permission blocks stop the test.

The writer opens `.gitignore` without following symbolic links, checks
file identity before reading and writing, and verifies it after writing.
New files require exclusive creation. Detected replacement stops Setup
without retries or reversion. These checks address replacement of the
`.gitignore` file, not replacement of the project directory itself.
Opening flags follow
[Ruby's file constants][file-constants].

[file-constants]: https://docs.ruby-lang.org/en/4.0/File/Constants.html

## Approved Storage Untracking

```sh
sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/setup/storage/storage_tracking_test.rb
```

Checks tracked-path parsing, authorization refusal, scoped cached
removal, rechecking, failures, CLI results, and Setup instructions.
Git is simulated with an injected command runner. These tests do not
modify a real Git index or prove installed-client prompt behavior.

## Real Git Storage Untracking

```sh
sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/setup/storage/storage_tracking_integration_test.rb
```

Uses the same dependency-free harness with real Git repositories under
the workspace's `.unclassified/` directory. Runs the Bundled Ruby
Launcher and tracking CLI, not command doubles or an installed client.

Checks detection despite ignore rules, refusal without approval,
approved untracking, local-file preservation, unrelated staged changes,
repeat calls, missing storage, staged-content conflicts, and index
locks.
Fixture commits use test-only identity values; global and system Git
configuration are excluded. No real project index or plugin installation
is changed. Fixtures are removed after testing. Any permission block
stops the suite without retries or workarounds.

These integration tests do not test the agent's approval conversation.
