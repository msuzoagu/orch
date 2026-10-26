# Error Reporting Policy

## Authority and Boundary

This policy defines how the primary-agent conductor, executable workflow
contracts, task-creation contracts, and delegated specialists report a
blocking failure.

A document is an executable contract when it directs an agent to perform
work and owns the resulting completion or halt outcome. Every executable
contract that can halt must list this policy as required reading and
apply it without redefining its rules.

Models, interfaces, schemas, and output templates are not executable
contracts when they do not own a completion or halt outcome.

An executable contract may define its halt label, normal output, and
exact error path, but must not redefine the reporting boundary or
outcomes below.

[ReportTemplate.md](ReportTemplate.md), in the same directory as this
policy, is the sole error-report schema.

An error outcome is not a successful specialist artifact and does not
advance orchestration.

## Error-Contract Validation Boundary

The error contract is validated only after all of the following are
confirmed:

1. every required executable contract and applicable task and
   instructions artifact is complete, readable, and valid;
2. every required runtime value and authority path is complete,
   readable, and valid;
3. the exact normal-output path and permitted filesystem changes are
   known;
4. the exact error path is authorized, distinct from the normal-output
   path, and absent;
5. `ReportTemplate.md` is complete and readable;
6. the caller to which the halt outcome must return is known; and
7. no artifact needed to establish the error contract contains an
   unresolved placeholder.

If an executable contract does not establish an exact error path, its
error contract remains unvalidated.

## Before Validation: Direct Halt

When a blocking failure occurs before the complete error contract is
validated:

1. stop the current procedure;
2. create no normal output or error artifact;
3. collect every failure that can be identified safely;
4. return the procedure's `Halted` status and complete
   failure list directly to its caller; and
5. perform no further procedure or orchestration transition.

A direct halt is a returned message, not a file. It must not identify or
imply that an error artifact exists.

The primary-agent conductor reports its own direct halt to the Human.

## After Validation: Error Artifact

When a blocking failure occurs after the complete error contract is
validated:

1. stop the normal procedure;
2. do not create, complete, repair, or overwrite the normal output;
3. make no additional error-reporting change except writing exactly one
   complete error artifact at the validated error path from
   `ReportTemplate.md`;
4. confirm that the completed error artifact is a readable regular file;
5. return the procedure's `Halted` status and exact error
   path to its caller; and
6. perform no further procedure or orchestration transition.

This policy does not authorize, preserve, revert, or otherwise determine
the disposition of repository changes made before the failure.
Applicable working-tree governance owns that decision.

## Mandatory Direct-Halt Fallback

Use **Before Validation: Direct Halt** whenever:

- the error path is missing, undefined, invalid, unreadable, or
  unusable;
- `ReportTemplate.md` is missing, unreadable, invalid, or unusable;
- the error artifact cannot be written completely to the validated path;
  or
- the completed error artifact cannot be confirmed as a readable regular
  file.

The direct halt must include the error-reporting failure. Do not select
another path, substitute another template, or create a partial error
artifact.

## Caller and Record Responsibility

A delegated specialist returns its halt to the role execution that
invoked it. A role execution returns its halt to the primary-agent
conductor. The primary-agent conductor reports the terminal outcome to
the Human.

Only the executable contract that owns the Orchestration Record may
update it. After accepting a valid halt outcome, that contract records
`Workflow Halted` without recording the error artifact as a
successful specialist result. A failure to persist the Record is
reported through a direct halt to the caller; it does not authorize a
substitute Record.

## Halt-Outcome Validation

A caller accepts exactly two halt forms:

- a direct halt containing the failure list and no error path; or
- a post-validation halt containing the exact validated error path.

If a halt matches neither form, the caller reports the
outcome-validation failure through a direct halt. It does not create,
repair, or substitute an error artifact.
