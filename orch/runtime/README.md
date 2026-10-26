# Runtime Delivery Proof

## Purpose

Prove that a helper can run with bundled Ruby from another project
directory and from a relocated plugin copy. This does not prepare
WorkRequest storage or change the Question skill.

## Runtime and Dependencies

This candidate supports macOS on Apple Silicon only. `runtime.json`
records Ruby 4.0.6, the verified checksum of the upstream archive
`ruby-4.0.6.macos.tar.gz`, and the gem versions used by the helper and
tests. The archive itself is not shipped; only its unpacked contents
are. Those gems ship in the downloaded runtime; the user does not
install Ruby or additional gems.

The runtime is in `portable-ruby/ruby-4.0.6/`. The older copied mise
installation in `../ruby/` is not used.

## Launcher and Runtime Delivery Diagnostic

`../scripts/ruby_launcher.sh` locates Ruby relative to itself,
not the current project directory. It sets `GEM_HOME`, `GEM_PATH`, and
`GEM_SPEC_CACHE` inside that runtime. It removes inherited Ruby load
options and automatic Bundler or gem-dependency activation settings.
These changes affect only the launched process.

The launcher accepts Ruby arguments. The caller identifies the helper
by its installed absolute path; the launcher preserves the caller's
working directory and returns Ruby's exit status. Missing runtime files
cause failure, never a fallback to system Ruby or mise.

`../scripts/runtime_delivery_diagnostic.rb` checks bundled runtime
delivery. It returns JSON containing the runtime path, working
directory, gem paths, loaded Ruby files, native dependencies, and a JSON
round-trip result. It performs no writes. macOS system libraries remain
operating-system dependencies, not bundled Ruby gems.

## Run the Runtime Delivery Diagnostic

From any permitted project directory, use the plugin's actual installed
path in place of `/path/to/orch`:

```sh
/bin/sh /path/to/orch/scripts/ruby_launcher.sh \
  /path/to/orch/scripts/runtime_delivery_diagnostic.rb
```

## Tests

The test harness is plain Ruby with explicit assertions. It introduces
no test-framework gem. From this repository root, run:

```sh
/bin/sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/runtime/runtime_delivery_test.rb
```

Tests use temporary directories under the Git-ignored `.unclassified/`
directory inside this workspace. They exercise a separate target
project directory, hostile inherited Ruby settings, a relocated runtime,
missing-runtime failure, argument forwarding, and exit-code propagation.
They check that Ruby files, gems, and non-system native libraries come
from the selected runtime. Generated fixtures are removed after testing.

## Verification Boundary

The runtime delivery test passed 64 assertions on macOS Apple Silicon
inside the active Codex sandbox. Outstanding Linux and Windows tests are
tracked in [DeferredWork.md][deferred-work].
Source and relocated runtimes loaded their own Ruby files, gems, and
non-system native libraries. Target project contents remained unchanged.
Shell and Ruby syntax checks also passed.

The missing-runtime test cases include valid platform configurations in
their temporary plugin directories. One case leaves the runtime
directory absent; the other supplies that directory but leaves Ruby
absent. Both cases require exit status 78 and empty standard output.
The error must identify the intended missing directory or executable.
A missing configuration cannot satisfy these assertions.

A relocated plugin fixture tests filesystem relocation, not installation
by Codex. Installing this candidate through the client and invoking its
helper in an actual external project remains a separate manual check.
This proof does not edit Codex configuration or change its permissions.

[deferred-work]:
  ../../architecture/in-review/DeferredWork.md
