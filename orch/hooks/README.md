# Question Setup Hook

## Scope

On `UserPromptSubmit`, recognize a prompt whose first non-whitespace
token is exactly `@orch:question`. Return `additionalContext`
instructing the agent to load and execute this plugin's Setup skill
before intake.
Other prompts produce no output. Every matching submission triggers it.

The hook does not execute Setup itself, grant authorization, modify
project files, or establish readiness. Executing Setup remains the
agent's responsibility. Question's instructions are unchanged.

## Components and Contracts

- `QuestionSetupHook`: accepts a payload through `call(payload:)` and
  an absolute Setup skill path through its constructor. Returns a hook
  response object for a matching prompt, otherwise `nil`. Invalid
  payloads raise `ArgumentError` or `KeyError`. Performs no filesystem
  access or command execution.
- `QuestionSetupHookEntryPoint`: reads JSON from stdin, calls the
  injected hook, and writes the response as JSON. Returns exit code
  `0` on success, including a nonmatch. Invalid input returns `2` with
  a diagnostic on stderr, which blocks submission in Codex. The
  entry point accepts no command-line arguments.
- `hooks.json`: registers the command using the Bundled Ruby Launcher.
  The plugin manifest references it explicitly. Codex must enable and
  trust this hook before it will run.

## Local Invocation Test

Use the existing dependency-free Ruby assertion harness pattern:

```sh
sh orch/scripts/ruby_launcher.sh \
  -I orch/tests \
  orch/tests/hooks/question_setup_hook_test.rb
```

Tests cover matching, nonmatching, invalid input, repeated invocation,
the configured command, and paths containing spaces. They do not run
Setup or change real project storage. A passing local test does not
prove hook loading or agent behavior in an installed Codex session.

## Installed Codex Invocation Test

1. Exit the target project's Codex session. From this plugin repository,
   refresh the installed plugin:

   ```sh
   codex plugin remove orch@orch-dev
   codex plugin add orch@orch-dev
   ```

2. Start a new Codex session in the target project. Enter `/hooks`,
   select `UserPromptSubmit`, and press Enter to view its handlers.
   Select the Orch handler whose command ends in `question_setup.rb`.
   Review the command, then press `t` to trust that handler. If
   disabled, press Space to enable it. Do not trust unrelated hooks.
3. Close the hook browser and submit:

   ```text
   @orch:question tell me about this project
   ```

   Confirm that the agent loads and executes Setup before Question
   intake. Setup may stop under its existing instructions; the hook
   does not add directory creation or bypass required authorization.

These client-test steps have not been executed by the repository tests.
