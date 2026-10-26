---
name: setup
description: >-
  Prepare project WorkRequest storage and Git exclusion when authorized.
  Use when the Human invokes setup or another skill requires project
  Setup. Creates wr/ if missing and preserves existing contents.
  Does not collect Questions or start WorkRequests.
---

# Project WorkRequest Storage Setup

## Responsibility and Current Capability

Setup owns the project's `wr/` directory and its Git-ignore setup.
Successful setup requires an existing, writable directory Git ignores.
No paths under `wr/` may remain in Git's index.
Preserve existing `.gitignore` contents and stored WorkRequests.

The Ruby helper validates both targets, ensures Git exclusion, and
creates `wr/` if missing. Invoke it only after explicit authorization.
Do not ask the Human to create the directory or use a shell substitute.

Follow the target project's instructions and permissions. If a required
operation is prohibited or blocked, report the failure and stop without
attempting a workaround. Do not add skill announcements or quotations
of these instructions to the setup interaction.

## Discover the Project Root

Every Setup Git command must skip global and system configuration while
retaining repository configuration. Apply the environment settings below
to that command only; do not modify the Human's configuration files or
permissions. If any permitted operation remains blocked, stop and report
the failure.

1. Obtain the target working directory from the agent client's workspace
   context. It may be a project subdirectory, not the repository root.
   If no target working directory is available, report that and stop.
2. Discover the Git working-tree root with this read-only command:

   ```sh
   /usr/bin/env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
     git -C "<target-working-directory>" rev-parse --show-toplevel
   ```

   Replace the placeholder with the actual directory. On success, retain
   the returned absolute project root. On failure, report the diagnostic
   and stop. Do not ask the Human for a project path, guess a root, or
   use the installed plugin's directory as the target.

## Check Setup Readiness

1. Use read-only filesystem checks on `<project-root>/wr/`. Reject a
   symbolic link, including a dangling link, or a non-directory. Report
   the invalid target and stop without writes. A missing directory is
   a setup requirement, not a failure; continue checking Git exclusion.
2. If the directory exists, check writability without creating files:

   ```sh
   test -w "<project-root>/wr/"
   ```

   Use the discovered project root. Exit code `0` means writable; `1`
   means not writable. If not writable, report the exact directory and
   stop. Do not change permissions or continue intake. If the check is
   blocked or otherwise fails, report the diagnostic and stop.

   For an unwritable directory, use the actual path and report only:

   > Setup stopped because `<project-root>/wr/` is not writable.
   > The directory must be writable before Setup can continue.
   > No files were changed.

   Do not append skill paths or instruction quotations to this report.
   If an earlier setup operation changed files or the Git index, replace
   "No files were changed" with an accurate account of those changes.

3. Check effective Git exclusion:

   ```sh
   /usr/bin/env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
     git -C "<project-root>" check-ignore -- wr/
   ```

   Replace the placeholder with the discovered root. Exit code `0`
   means ignored; `1` means not ignored. Any other exit code is a
   failure: report the diagnostic and stop. A `/wr/` line alone is not
   proof.
4. Locate the installed plugin root from this loaded skill's path:
   `<plugin-root>/skills/setup/SKILL.md`. Check Git tracking, even if
   `wr/` is missing or ignored:

   ```sh
   sh "<plugin-root>/scripts/ruby_launcher.sh" \
     "<plugin-root>/lib/orch/setup/storage/manage_storage_tracking.rb" \
     check "<project-root>"
   ```

   Use actual absolute paths. On success, stdout is a JSON array of
   tracked paths. An empty array means none are tracked. On failure,
   report the diagnostic and stop. A Git-ignore result does not prove
   existing files are untracked.
5. If tracked paths exist, follow Untracking Authorization below before
   any setup writes. Otherwise, continue to the readiness result.
6. If storage exists, is writable, ignored, and untracked, report:

   > WorkRequest storage is ready: `<project-root>/wr/`.

   Use the actual path. Stop without requesting authorization or writing
   files. Otherwise, continue to setup authorization.

## Untracking Authorization

Display the tracked paths from the check, followed by this prompt:

> Git already tracks these paths under `<project-root>/wr/`.
> WorkRequest storage must be untracked before Setup can continue.
> May I untrack them while keeping their local copies?

1. **Yes:** untrack the files for me, without committing.
2. **No:** I will run the command myself.

End the turn and wait for an explicit answer. No answer or an unclear
answer remains pending; do not change files or the Git index. Do not
append skill paths, instruction quotations, or intake status.

On **No**, display this command using the actual project root and stop:

```sh
git -C "<project-root>" rm -r --cached -- wr/
```

Explain that this stages removal from Git tracking, preserves local
copies, and does not commit. The Human can review the staged change and
rerun Setup. Do not run it on their behalf.

On **Yes**, invoke only the approved untracking operation:

```sh
sh "<plugin-root>/scripts/ruby_launcher.sh" \
  "<plugin-root>/lib/orch/setup/storage/manage_storage_tracking.rb" \
  untrack "<project-root>" --approved
```

The `--approved` flag records the caller's authorization assertion; it
is not evidence of approval. Supply it only after the Human answers Yes
to this untracking prompt. Storage-creation approval does not authorize
untracking. Untracking approval does not authorize other setup writes.

The helper rechecks tracking before returning success. On failure,
report the diagnostic and stop without force, retries, or reversion.
The index may have changed; do not claim nothing changed. On success,
repeat the read-only readiness checks. Continue Setup only if no storage
paths remain tracked. Do not commit, delete files, or change branches.

## Obtain Setup Authorization

If storage is missing or not ignored, present this question using the
actual project root and Yes/No choices:

> May I prepare WorkRequest storage at `<project-root>/wr/`?
> This creates `wr/` if missing and creates or updates
> `<project-root>/.gitignore` to exclude `/wr/` if needed, preserving
> existing contents.

Present only the authorization prompt and Yes/No choices. End the turn
and wait for the Human's explicit answer. Do not append skill paths,
instruction quotations, authorization explanations, or Question-intake
status. Do not invoke the helper while the answer is pending.
A displayed or preselected choice is not approval.

- **Yes:** continue to prepare storage.
- **No:** stop without additional changes.
- **No answer or an unclear answer:** remain pending; do not write.

## Prepare Storage

1. Locate the installed plugin root from this loaded skill's path:
   `<plugin-root>/skills/setup/SKILL.md`. Use its Bundled Ruby Launcher
   and Ruby entry point, not a development copy.
2. Invoke the existing preparation operation:

   ```sh
   sh "<plugin-root>/scripts/ruby_launcher.sh" \
     "<plugin-root>/lib/orch/setup/storage/prepare_storage.rb" \
     "<project-root>"
   ```

   Replace placeholders with their actual absolute paths. Pass the
   discovered project root as one argument. Do not use system Ruby.
3. On a nonzero exit code, report the diagnostic and stop. Do not claim
   setup succeeded or silently undo completed changes.
4. On success, retain the absolute storage path returned on stdout.
   Repeat the read-only readiness checks. Report storage ready only if
   the directory exists, is not a symbolic link, is writable, and Git
   ignores it, and no storage paths remain tracked.
   If any check fails, report failure and stop; do not prompt again or
   silently repeat preparation.

## Stop After Setup

Do not collect or answer a Question, allocate a `wr-key`, create a
Record or artifacts, create or switch branches, or commit files,
or start Investigation. Setup does not start a WorkRequest. Do not
automatically start a Question invocation. If Question invoked Setup,
return to that same invocation only after Setup succeeds, preserving
its supplied Question; do not require another submission.
The only permitted index change is explicitly approved untracking of
storage paths; it is separate from WorkRequest implementation staging.
