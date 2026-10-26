# Commit Procedure

## Purpose

This procedure creates and verifies one preservation commit on the
owning WorkRequest branch from an exact list of validated paths supplied
by the primary conductor.

It does not select paths, validate artifact semantics, authorize
application changes, alter file contents, create branches, integrate
code, amend history, or push. A commit does not prove implementation
correctness or authorize integration.

Target-project permissions take precedence. This document is not
permission to run Git commands prohibited by those instructions.

## Required Documents

Read completely before proceeding:

- [Policy.md](../error-reporting/Policy.md)
- [ReportTemplate.md](../error-reporting/ReportTemplate.md)
- [WorkingTreePolicy.md](WorkingTreePolicy.md)
- [CommitPolicy.md](CommitPolicy.md)

The caller must also supply the applicable execution and Record
validation contracts. Do not import the legacy `RecordStorage.md`
contract or assume Markdown Record persistence rules apply to JSON.

## Required Inputs

- `ExpectedHead`: complete commit ID for the producing work's starting
  baseline, established by its execution contract.
- `WorkRequestBranch`: exact branch whose recorded ownership belongs
  to this WorkRequest.
- `WorkRequestStorageRoot`: configured repository-relative storage root
  in the target project, not inside the installed plugin package.
- `RecordPath`: exact validated repository-relative path to the owning
  `Record.json`.
- `ValidatedPaths`: non-empty list of exact repository-relative
  changed paths.
- The commit's purpose, applicable classification and message contract,
  and evidence that its contents and application changes are authorized.

For a currently defined orchestration-only action, also require:

- `CommitAction`: exactly `prepare`, `complete`, or `halt`.
- `State`: exact State or procedure name supplied by its contract.

For implementation preservation, require explicit Human authority for
the application changes, their exact permitted paths, and validation of
the implementation output and corresponding Record update. Successful
Verification is not required to preserve this snapshot.

Initial Record, gate-resolution, abandonment, and implementation
preservation message formats are not yet defined. Halt before staging
for any purpose without its required classification and message
contract.
Do not substitute `record entry`, `fix:`, or `feat:` for missing rules.

If a commit covers a completed State or resolved gate, require its
corresponding validated Record update among `ValidatedPaths`. The
caller must establish what completed or what the Human decided; this
procedure must not invent those facts.

Reject duplicate paths, absolute paths, path traversal, unresolved
placeholders, control characters, and incomplete inputs.
`ValidatedPaths` and `RecordPath` must identify file paths, not
directory-only paths.

Confirm `WorkRequestStorageRoot` matches the configured target-project
storage root. Do not infer it from `RecordPath` or the current working
directory.

Confirm `RecordPath` is a readable, validated regular file at exactly:

```text
<WorkRequestStorageRoot>/<wr-key>/Record.json
```

Confirm the Record's `wr-key` matches the single directory
component immediately beneath `WorkRequestStorageRoot`. Reuse that key;
do not allocate another or accept disagreement between Record and path.

For orchestration-only commits, confirm every `ValidatedPath` belongs
beneath that exact owning WorkRequest directory. Reject paths belonging
to another WorkRequest or the plugin package.

## Branch and Pre-Commit Validation

1. Confirm the current branch equals `WorkRequestBranch`. Confirm the
   caller's validated ownership identifies this exact WorkRequest.
   Detached HEAD or a missing ownership contract must halt the
   operation.
2. Confirm `HEAD^{commit}` equals `ExpectedHead`.
3. Run:

   ```text
   git status --porcelain=v1 -z --untracked-files=all
   ```

4. Parse the complete NUL-delimited result without shell interpretation.
5. Confirm its exact changed-path set equals `ValidatedPaths`.
6. Confirm no unmerged entry exists.
7. Confirm the Git index contains no pre-existing staged change.
8. Validate the configured storage root, owning Record, matching key,
   authorized path set, and commit message contract.
9. Apply the ownership, preservation, and authorization rules in
   `CommitPolicy.md`. Reject files owned by another WorkRequest.

Do not stage anything unless every check passes.

## Message Construction

Construct one subject from the validated inputs.

For a defined orchestration-only action, use the matching exact form:

- `orchestration: prepare <State> for <wr-key>`
- `orchestration: complete <State> for <wr-key>`
- `orchestration: halt <State> for <wr-key>`

Use the owning `wr-key`, already confirmed against its Record
and storage directory, in these forms.

For other purposes, use only an explicitly established message contract.
If none exists, halt before staging. Never describe an unverified
snapshot as successfully verified, approved for integration, or
released.
Abandonment may be recorded only after the Human's abandonment decision.

The constructed subject must be one non-empty line with no control
character. Do not add a body.

## Stage and Validate

Reconfirm the owning branch and `ExpectedHead` immediately before
staging. Pass the sorted `ValidatedPaths` as separate arguments after
`--`:

```text
git add -- <ValidatedPath>...
```

Then rerun the NUL-delimited status command and inspect the complete
staged diff. Confirm:

- every `ValidatedPath` is staged;
- no other path is staged;
- no unstaged or untracked change remains; and
- the staged change is non-empty.

Do not continue when any check fails.

## Commit

Reconfirm the owning branch and `ExpectedHead` before committing.
Pass the constructed subject as one argument without invoking a shell:

```text
git commit -m <ConstructedSubject>
```

Create exactly one commit. Do not amend, merge, tag, push, switch
branches, or delete branches.

## Post-Commit Verification

After `git commit` succeeds, confirm all of the following:

1. The current branch still equals `WorkRequestBranch`.
2. `HEAD^{commit}` exists and differs from `ExpectedHead`.
3. The new commit has exactly one parent, equal to `ExpectedHead`.
4. Its subject equals `ConstructedSubject` and it has no body.
5. Its complete changed-path set equals `ValidatedPaths`.
6. Its purpose, message, ownership, and paths satisfy `CommitPolicy.md`.
7. `git status --porcelain=v1 -z --untracked-files=all` returns no
   record.

Return `Commit Complete`, the complete new commit ID, and its
subject only when every verification passes. This result confirms commit
creation, not implementation correctness or permission to integrate.

The caller retains the commit identity through its owning Record
contract. Do not modify the Record after committing inside this
procedure; that would create another uncommitted change.

## Halt Behavior

Apply [Policy.md](../error-reporting/Policy.md) without redefining its
validation boundary. An error-artifact halt requires an exact authorized
error path and the complete validated error contract. Otherwise return
the direct-halt failure list, including any error-reporting failure.

Return `Commit Halted` with the policy's applicable halt form. Do not
reset, restore, revert, clean, stash, amend, retry, or push. Do not
advance orchestration. Preserve the actual repository state, including
any staged changes or commit created before a later check failed.
Do not claim no commit was created when post-commit verification failed.
