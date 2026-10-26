---
name: question
description: >-
  Invoke the Setup skill first on every invocation, before collecting
  the Human's exact Question.
  Use when the Human invokes question to submit a new Question for
  investigation. Does not investigate or answer the Question.
---

# Question WorkRequest Intake

## Implemented Scope

Run Setup before Question intake on every invocation. Setup owns project
root discovery, storage checks, and authorized Git-ignore changes.
Question owns preserving and collecting the Question after Setup
succeeds. No orchestration State is executed.

Treat each explicit invocation as intake for a new Question WorkRequest,
not continuation of an existing WorkRequest. Installation alone must not
start intake or any orchestration work.

Follow the target project's applicable instructions and permissions.

## Run Setup First

On every `@orch:question` invocation, invoke the Setup skill first:

1. Read [Setup's instructions](../setup/SKILL.md) in their entirety.
   Resolve this path relative to the loaded Question skill's directory,
   using the same installed plugin. If unreadable or missing, report
   the failure and stop.
2. Execute Setup's workflow before Question intake. Reading the file
   alone is not invoking Setup. Do not skip Setup because it ran before
   or ask the Human to invoke it separately. Follow its instructions
   for authorization, waiting, and stopping.
3. Preserve any supplied Question text verbatim while Setup runs.
   Resume this same invocation's Question intake only after Setup
   succeeds; do not require another invocation or resubmission.

While Setup awaits authorization, end the turn at its prompt and
choices. Do not append skill paths, instruction quotations, explanations
of the authorization requirement, or Question-intake status.

## Collect the Question

1. If the Human supplied Question text containing at least one
   non-whitespace character with the skill invocation, preserve it
   exactly and do not ask them to submit it again. The skill invocation
   itself is not Question text.
2. Otherwise, ask:

   > What question would you like investigated?

   Wait for the Human's response. An empty or whitespace-only response
   is not a submitted Question; ask for the Question again.
3. Preserve the submitted Question verbatim. Do not infer, paraphrase,
   broaden, answer, or investigate it.
4. Display the received Question verbatim, followed by:

   > Question received. Investigation has not started.

## Stop After Question Intake

Do not create `wr/`, allocate a `wr-key`, create or check out a branch,
start policy bootstrap, create a Record or artifacts, delegate to
specialists, or execute any orchestration State. Leave storage
management to Setup. Do not claim that WorkRequest startup or
Investigation occurred.
