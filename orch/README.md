# Orchestration Plugin

## Install Locally

1. Open this repository in Codex.
2. Open the plugin browser. In Codex CLI, enter `/plugins`.
3. Select the `orch-dev` marketplace and install `orch`.
4. Start a new session before invoking the bundled Question skill.

The repository's `.agents/plugins/marketplace.json` points to
`./orch`. Installation is performed by the client, not by a
plugin script. Ruby, SQLite, and RuboCop are not required for this
Question-intake-only portion.

See OpenAI's
[local installation instructions](https://developers.openai.com/plugins/build/plugins#install-a-local-plugin-manually)
and
[plugin browser instructions](https://learn.chatgpt.com/docs/plugins#plugin-browser-in-codex-cli).

## Start a Question WorkRequest

Select the plugin's `question` skill using the client's skill picker.
Supply the Question with the invocation, or invoke without Question text
and answer:

> What question would you like investigated?

The skill preserves the Question exactly, displays it, and stops.
An empty or whitespace-only response causes it to ask again.

This portion does not allocate a key, create storage or a Record, or
start Investigation. Installing the plugin does not start a WorkRequest.

## Check the Intake Behavior

- With Question text: display it unchanged without asking again.
- Without Question text: ask the prompt above and wait for a response.
- With an empty response: ask again rather than accepting it.
- After receiving a Question: stop without answering it or creating
  files.

## Bundled Runtime Proof

A separate launcher and `runtime_delivery_diagnostic.rb` test bundled
Ruby delivery. They are not called by the Question skill and do not
prepare WorkRequest storage. See [the runtime proof](runtime/README.md)
for dependencies, commands, tests, and installed-client verification.
