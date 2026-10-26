# Commit Policy

## Purpose

This policy is the sole authority for what may be committed, who may
commit, when implementation must be committed, and when integration is
permitted.

## What to Commit

Commit only changes that constitute the implemented solution:
implementation code, tests, configuration, and migrations.

## What Not to Commit

Do not commit WorkRequest artifacts: Records, findings, assessments,
specifications, plans, approvals, verification reports, error reports,
or task instructions.

## Who Commits

Only the primary conductor may stage and commit. Use
[CommitProcedure.md](CommitProcedure.md) with the exact permitted
paths.

Commit authorization does not authorize amendments, history rewriting,
pushing, or merging.

## When to Commit

Commit the implementation on its owning WorkRequest branch only after
Implementation is complete.

Unverified or deficient implementation may be preserved on that branch;
its commit must not claim successful Verification.

State completion or DecisionGate resolution alone does not require
a commit.

Abandonment does not authorize deleting the branch or committed work.

## When Integration Is Permitted

Integrate only successfully verified implementation, with separate,
explicit Human authorization and an identified destination branch.

Verification must identify the exact implementation commit examined.
Implementation changes after that commit require new Verification.

A preservation commit does not authorize integration or release.
