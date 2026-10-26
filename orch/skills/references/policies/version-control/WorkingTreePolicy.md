# Working-Tree Policy

## Purpose

This policy is the sole authority for WorkRequest branch ownership,
WorkRequest branch boundaries, and permitted changed paths.

It does not define artifact semantics, commit ownership, commit
messages, Git commands, or release behavior.

The plugin creates an owning branch for each new WorkRequest and commits
only its Implementation outputs. It does not enforce project
working-tree cleanliness. Integration requires separate Human
authorization, which occurs only after successful Implementation
Verification when the Human chooses whether to merge into a specified
local branch, push the WorkRequest branch and create a Pull Request
targeting a specified branch, or leave the WorkRequest branch unchanged.

## Clean Working Tree

The plugin does not enforce project working-tree cleanliness.

## WorkRequest Branch Boundary

Each new WorkRequest requires a unique WorkRequest key and its own Git
branch. Keep the owning branch checked out throughout WorkRequest
orchestration, except when switching to the specified destination
branch for a Human-authorized local merge after successful
Implementation Verification. The conductor commits the WorkRequest’s
Implementation outputs to its owning branch.

Before Implementation changes or Implementation commits, confirm that
the current branch is the owning WorkRequest branch. A branch name alone
is not evidence of ownership; the owning execution contract must supply
the recorded association.

Do not implement directly on the integration or release branch. Branch
creation, naming, and ownership-record fields remain to be defined.
Do not infer those conventions or create a branch without its required
creation contract.

## Implementation Commit Boundary

Commit the WorkRequest’s Implementation outputs to its owning branch
after Implementation is complete and before Implementation
Verification begins. Implementation outputs are project-file changes
implementing the tests, tasks, and plans in `TestPlan.md`,
`ImplementationTaskPlan.md`, and the approved `ImplementationPlan.md`.
Use [CommitPolicy.md](CommitPolicy.md) for commit authorization.

An implementation snapshot must be committed on the WorkRequest branch
before Verification starts. This preserves unverified implementation;
it does not establish verification success or integration authority.

Parallel reviews do not authorize concurrent writes or commits in a
shared working tree. Their isolation remains to be defined.
Do not launch concurrent writers without those contracts; do not infer
isolation from different branch names.

## Permitted Changes During Execution

The WorkRequest may modify only the exact paths permitted by its
current execution contract. Preserve the exact starting commit identity
so the commit procedure can detect a changed baseline.

A WorkRequest change is unauthorized when that contract does not
explicitly permit it. Permission must not be inferred from a prior state
or from membership in an otherwise permitted directory. A WorkRequest
branch does not authorize unrelated changes or changes belonging to
another WorkRequest.

## Verification, Abandonment, and Correction

Verification must identify the exact implementation commit examined.
Later code changes are not covered by that verification. Successful
verification does not automatically merge the WorkRequest branch.

Abandonment preserves the WorkRequest branch, code, Record, and
evidence.
It does not authorize branch deletion, reversion, or disposal of work.

A correction WorkRequest requires a new key and its own branch, starting
from an exact recorded commit containing the deficient implementation. 

Its execution contract must establish the source commit and references
to the original Record, approved artifacts, and verification findings.

## Failure Handling

If the WorkRequest modifies an unauthorized path, halt before the
next transition. Do not delete, revert, stash, clean, repair, or
normalize the change. Report the failure through
[Policy.md](../error-reporting/Policy.md). A halt does not authorize a
successor State or a Human DecisionGate.

## Commit-Governance Boundary

[CommitPolicy.md](CommitPolicy.md) governs whether validated changes
must be committed and who may initiate that operation. This policy
neither authorizes a commit nor defines how one is created.
